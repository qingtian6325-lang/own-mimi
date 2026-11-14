import Foundation
import Combine

public struct AICategoryTableRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let primaryCategory: String
    public let subcategoriesText: String

    public init(id: UUID = UUID(), primaryCategory: String, subcategoriesText: String) {
        self.id = id
        self.primaryCategory = primaryCategory
        self.subcategoriesText = subcategoriesText
    }
}

public enum AIChatResponseBlock: Equatable, Sendable {
    case text(String)
    /// 问账等待态：回复到达前显示「咪咪思考中…」，回复/报错后被整块替换。
    case pendingAnswer
    case draftBills([ParsedDraftBill])
    case categoryTable(expenseRows: [(String, String)], incomeRows: [(String, String)], customNote: String)
    case spendingSummary(title: String, amount: Double, count: Int, details: String)

    public static func recognizedBills(_ drafts: [ParsedDraftBill]) -> AIChatResponseBlock {
        .draftBills(drafts)
    }

    public static func == (lhs: AIChatResponseBlock, rhs: AIChatResponseBlock) -> Bool {
        switch (lhs, rhs) {
        case let (.text(a), .text(b)):
            return a == b
        case (.pendingAnswer, .pendingAnswer):
            return true
        case let (.draftBills(a), .draftBills(b)):
            return a == b
        case let (.categoryTable(ea, ia, na), .categoryTable(eb, ib, nb)):
            return ea.map(\.0) == eb.map(\.0) && ia.map(\.0) == ib.map(\.0) && na == nb
        case let (.spendingSummary(ta, aa, ca, da), .spendingSummary(tb, ab, cb, db)):
            return ta == tb && abs(aa - ab) < 0.001 && ca == cb && da == db
        default:
            return false
        }
    }
}

public typealias AIChatMessage = AIChatMessageItem

public struct AIChatMessageItem: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var isUser: Bool
    public var userText: String
    public var blocks: [AIChatResponseBlock]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        isUser: Bool,
        userText: String = "",
        blocks: [AIChatResponseBlock] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.isUser = isUser
        self.userText = userText
        self.blocks = blocks
        self.createdAt = createdAt
    }

    public var hasDraftBills: Bool {
        blocks.contains(where: { block in
            if case .draftBills = block { return true }
            return false
        })
    }

    public var draftBills: [ParsedDraftBill] {
        blocks.flatMap { block -> [ParsedDraftBill] in
            if case .draftBills(let drafts) = block { return drafts }
            return []
        }
    }
}

@MainActor
public final class MimiAIEngine: ObservableObject {
    @Published public var messages: [AIChatMessageItem] = []
    /// 正在思考 / 识别中（全屏等待态）
    @Published public var isAnswering: Bool = false
    /// 本轮回答刚完成，UI 可短暂显示「回答完毕」
    @Published public var answerJustCompleted: Bool = false
    /// 用户消息附带的图片（仅内存，用于气泡缩略图）
    @Published public var userMessageImages: [UUID: [Data]] = [:]

    // 旧版自定义大模型设置（v1.2.0 起识别/问账统一走 Gemini；Key 不再写 UserDefaults）
    @Published public var apiKey: String = ""
    @Published public var apiBaseURL: String = UserDefaults.standard.string(forKey: "mimi_llm_base_url") ?? "https://api.deepseek.com/v1"
    @Published public var apiModel: String = UserDefaults.standard.string(forKey: "mimi_llm_model") ?? "deepseek-chat"

    public var customAPIKey: String {
        get { apiKey }
        set { apiKey = newValue }
    }

    public var customAPIBaseURL: String {
        get { apiBaseURL }
        set { apiBaseURL = newValue }
    }

    public static let presetPromptChips: [String] = [
        "可以增加或删除某个分类吗？",
        "怎样获得更多VIP时长？",
        "怎样加入共享账本？"
    ]

    /// 金标 AI 记账空状态建议气泡（点即发送）
    public static let exampleQuestions: [String] = [
        "查询本月单笔消费超过200块的账单",
        "查看我最近3天的消费记录？",
        "我最近一次购物买了什么？"
    ]

    public init() {
        clearLegacyPlaintextAPIKeyIfNeeded()
        loadHistory()
    }

    /// 清除 v1.2.0 之前可能残留在 UserDefaults 的明文 LLM Key。
    public func clearLegacyPlaintextAPIKeyIfNeeded() {
        if UserDefaults.standard.object(forKey: "mimi_llm_api_key") != nil {
            UserDefaults.standard.removeObject(forKey: "mimi_llm_api_key")
        }
    }

    public func saveAPISettings(key: String, baseURL: String, model: String) {
        // Key 故意不落盘：旧自定义 LLM 通道已废弃，避免再把密钥写进 UserDefaults。
        self.apiKey = ""
        self.apiBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.removeObject(forKey: "mimi_llm_api_key")
        UserDefaults.standard.set(self.apiBaseURL, forKey: "mimi_llm_base_url")
        UserDefaults.standard.set(self.apiModel, forKey: "mimi_llm_model")
        _ = key
    }

    // MARK: - Natural Language Bill Parsing

    /// Splits a single natural-language input into one or more `ParsedDraftBill` items ("一句话记多笔").
    /// Supports both punctuation delimiters ("，,；;\n") and whitespace between an amount and the next keyword (e.g. "午饭 24.5 咖啡 12.9 打车 18"),
    /// without splitting inside dates/times such as "11月8日 午饭 25", "2026-11-08 午饭 25", or "晚上8点 宵夜 30".
    public func parseNaturalLanguageBills(
        _ input: String,
        now: Date = Date(),
        preferredAccountId: String? = nil,
        preferredAccountName: String? = nil,
        timeZone: TimeZone = .current
    ) -> [ParsedDraftBill] {
        let separators = CharacterSet(charactersIn: "，,；;\n")
        let rawClauses = input
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .flatMap { splitClauseOnAmounts($0, now: now, timeZone: timeZone) }

        var drafts: [ParsedDraftBill] = []
        var carryDate = now
        for clause in rawClauses {
            let parsedDate = MimiNaturalLanguageDateParser.parse(
                in: clause,
                now: now,
                fallbackDate: carryDate,
                timeZone: timeZone
            )
            if parsedDate.hasExplicitDateOrTime {
                carryDate = parsedDate.date
            }
            let textWithoutDate = parsedDate.strippedText
            guard let amountMatch = extractAmountMatch(from: textWithoutDate), amountMatch.value > 0 else { continue }
            let isIncome = detectIncome(in: clause)
            let (accountId, accountName) = detectAccount(
                in: clause,
                preferredAccountId: preferredAccountId,
                preferredAccountName: preferredAccountName
            )
            let (primaryId, subId, categoryDisplay) = detectCategory(in: clause, isIncome: isIncome)
            let rawNote = cleanClauseNote(textWithoutDate, removingAmountRange: amountMatch.range)
            let finalNote = rawNote.isEmpty ? (categoryDisplay.components(separatedBy: "-").last ?? categoryDisplay) : rawNote
            drafts.append(
                ParsedDraftBill(
                    type: isIncome ? .income : .expense,
                    amount: amountMatch.value,
                    currency: .myr,
                    primaryCategoryId: primaryId,
                    subCategoryId: subId,
                    categoryDisplayName: categoryDisplay,
                    accountId: accountId,
                    accountDisplayName: accountName,
                    merchantOrNote: finalNote,
                    occurredAt: parsedDate.date
                )
            )
        }
        return drafts
    }

    /// 从账本里取最近一笔有账户的交易，作为自然语言记账默认账户。
    public static func preferredAccount(from store: MimiStore) -> (id: String, name: String)? {
        guard let tx = store.transactions.first(where: { $0.accountId != nil || !$0.accountName.isEmpty }) else {
            return nil
        }
        // resolveAccountId 返回 String?；必须解包成非可选，否则 macOS host 编译报
        // cannot convert '(String?, String)' to '(id: String, name: String)'
        guard let id = tx.accountId ?? DefaultCatalog.resolveAccountId(from: tx.accountName) else {
            return nil
        }
        let name = DefaultCatalog.resolveAccountName(from: id)
        return (id: id, name: name)
    }

    // MARK: - Chat Flow (UI 入口)

    /// 聊天发送主流程（可附带图片，一次发送）。
    public func handleUserMessage(_ message: String, store: MimiStore) {
        sendComposed(text: message, imageDataList: [], store: store)
    }

    /// 文字 + 图片一次发送：先出用户气泡 → 思考中 → 识别图/答问 → 「回答完毕」。
    public func sendComposed(text: String, imageDataList: [Data], store: MimiStore) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !imageDataList.isEmpty else { return }
        BookkeepingEntryPreference.rememberAI()
        answerJustCompleted = false

        var userLabel = trimmed
        if !imageDataList.isEmpty {
            let photoNote = imageDataList.count == 1 ? "[照片 1 张]" : "[照片 \(imageDataList.count) 张]"
            userLabel = trimmed.isEmpty ? photoNote : "\(photoNote)\n\(trimmed)"
        }
        let userMessage = AIChatMessageItem(isUser: true, userText: userLabel, blocks: [.text(userLabel)])
        if !imageDataList.isEmpty {
            userMessageImages[userMessage.id] = imageDataList
        }
        messages.append(userMessage)

        let placeholder = AIChatMessageItem(isUser: false, userText: "", blocks: [.pendingAnswer])
        messages.append(placeholder)
        isAnswering = true
        saveHistory()

        let placeholderId = placeholder.id
        let providerName = AIEngineSettings.provider.displayName
        Task { [weak self] in
            guard let self else { return }
            var replyBlocks: [AIChatResponseBlock] = []

            // 1) 图片 → 识别草稿
            var drafts: [ParsedDraftBill] = []
            var recognizeErrors: [String] = []
            for (idx, data) in imageDataList.enumerated() {
                do {
                    let result = try await SmartReceiptRecognizer.recognize(imageData: data)
                    drafts.append(result.draft)
                    if result.isSuspiciousAmount {
                        recognizeErrors.append("第\(idx + 1)张金额可疑，请仔细核对。")
                    }
                } catch {
                    let reason = (error as? ReceiptRecognitionFailure)?.dialogText
                        ?? error.localizedDescription
                    recognizeErrors.append("第\(idx + 1)张：\(reason)")
                }
            }
            if !drafts.isEmpty {
                var preface = "小金主，已从照片识别出 \(drafts.count) 笔账单草稿，核对无误后点「确认记账」才会入账："
                if !recognizeErrors.isEmpty {
                    preface += "\n" + recognizeErrors.joined(separator: "\n")
                }
                replyBlocks.append(.text(preface))
                replyBlocks.append(.draftBills(drafts))
            } else if !imageDataList.isEmpty && !recognizeErrors.isEmpty {
                replyBlocks.append(.text("小金主，照片没识别成功：\n" + recognizeErrors.joined(separator: "\n")))
            }

            // 2) 文字 → 记账句 / 本地答 / 联网问
            if !trimmed.isEmpty {
                let preferred = Self.preferredAccount(from: store)
                let textDrafts = self.parseNaturalLanguageBills(
                    trimmed,
                    preferredAccountId: preferred?.id,
                    preferredAccountName: preferred?.name
                )
                if BillMessageClassifier.classify(trimmed, draftCount: textDrafts.count) == .billDraft {
                    replyBlocks.append(.text("另外从你的文字里识别出 \(textDrafts.count) 笔草稿："))
                    replyBlocks.append(.draftBills(textDrafts))
                } else if let local = LocalBookkeepingAnswerer.blocks(for: trimmed, in: store) {
                    replyBlocks.append(contentsOf: local)
                } else if AIEngineSettings.hasAPIKey {
                    do {
                        let answer: String
                        switch AIEngineSettings.provider {
                        case .groq:
                            answer = try await GroqClient.answerQuestion(trimmed, store: store)
                        case .gemini:
                            answer = try await GeminiClient.answerQuestion(trimmed, store: store)
                        }
                        AIEngineSettings.recordCallStatus(success: true, message: "问账成功（\(providerName)）")
                        replyBlocks.append(.text(answer))
                    } catch {
                        let reason = (error as? GeminiError)?.description ?? error.localizedDescription
                        AIEngineSettings.recordCallStatus(success: false, message: "问账失败：\(reason)")
                        replyBlocks.append(.text("问账暂时不可用：\(reason)。"))
                    }
                } else if imageDataList.isEmpty {
                    let provider = AIEngineSettings.provider
                    replyBlocks.append(.text("小金主，这个问题要联网查账：请先到「设置 → AI 识别引擎」填入 \(provider.displayName) API Key（\(provider.keyApplyHint)）。"))
                }
            }

            if replyBlocks.isEmpty {
                replyBlocks = [.text("小金主，我这边没有生成内容。你可以再说一次，或发更清楚的付款截图。")]
            }

            self.replaceMessageBlocks(id: placeholderId, blocks: replyBlocks)
            self.isAnswering = false
            self.answerJustCompleted = true
            self.saveHistory()
        }
    }

    /// 兼容旧调用：只返回本地应答块（分类表/本地汇总/记账草稿/兜底提示），不发网络请求。
    public func handleUserMessage(_ message: String, in store: MimiStore) async -> [AIChatResponseBlock] {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return buildReplyBlocks(for: trimmed, in: store)
    }

    // MARK: - Draft Confirm / Cancel（确认才入账）

    public func confirmDrafts(messageId: UUID, in store: MimiStore) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        let drafts = messages[idx].draftBills
        guard !drafts.isEmpty else { return }
        var summaries: [String] = []
        for draft in drafts {
            let saved = ShortcutActionCoordinator.recordRecognizedDraft(draft, in: store)
            summaries.append("\(saved.categoryPath) \(MimiTheme.formatRM(saved.amount))")
        }
        messages[idx].blocks = [.text("✅ 已记账：\(summaries.joined(separator: "；"))")]
        saveHistory()
    }

    public func cancelDrafts(messageId: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        guard messages[idx].hasDraftBills else { return }
        messages[idx].blocks = [.text("已取消，这笔草稿没有入账。")]
        saveHistory()
    }

    /// 相册/拍照识别出的草稿进入聊天，同样走确认才入账。
    public func appendRecognizedDraft(
        _ draft: ParsedDraftBill,
        sourceLabel: String,
        isSuspiciousAmount: Bool = false
    ) {
        let preface: String
        if isSuspiciousAmount {
            preface = "小金主，已从\(sourceLabel)识别出账单，但金额看起来不太对劲（可能是误读）。请仔细核对后再点「确认记账」；没把握就先取消，改用一句话记账："
        } else {
            preface = "小金主，已从\(sourceLabel)识别出这笔账单草稿，核对无误后点「确认记账」才会入账："
        }
        messages.append(
            AIChatMessageItem(isUser: false, userText: "", blocks: [
                .text(preface),
                .draftBills([draft])
            ])
        )
        saveHistory()
    }

    /// 相册/拍照识别失败时如实告知：不生成草稿、不落账，并给出可行的下一步。
    public func appendRecognitionFailure(_ dialogText: String, sourceLabel: String) {
        messages.append(
            AIChatMessageItem(isUser: false, userText: "", blocks: [
                .text("小金主，\(sourceLabel)这张图没识别成。\(dialogText) 你可以换一张更清楚的截图再发，或直接用一句话把这笔账告诉我（例如：午餐 38）。")
            ])
        )
        saveHistory()
    }

    private func replaceMessageBlocks(id: UUID, blocks: [AIChatResponseBlock]) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].blocks = blocks
    }

    // MARK: - Local Answers

    private func buildReplyBlocks(for trimmed: String, in store: MimiStore) -> [AIChatResponseBlock] {
        if let local = LocalBookkeepingAnswerer.blocks(for: trimmed, in: store) {
            return local
        }
        let preferred = Self.preferredAccount(from: store)
        let drafts = parseNaturalLanguageBills(
            trimmed,
            preferredAccountId: preferred?.id,
            preferredAccountName: preferred?.name
        )
        if !drafts.isEmpty {
            return [
                .text("小金主，咪咪已为你识别并拆分出 \(drafts.count) 笔账单，点击下方确认即可入账："),
                .draftBills(drafts)
            ]
        }
        return [
            .text("你可以直接对我说“今天午饭吃餐厅8.30，TNG零食5.90”来一句话记多笔，或者问我“这个月花了多少”、“可以增加或删除某个分类吗？”")
        ]
    }

    // MARK: - Chat History Persistence（本地文件，杀进程重开还在）

    private struct PersistedChatMessage: Codable {
        var isUser: Bool
        var text: String
        var drafts: [ParsedDraftBill]
        var createdAt: Date
    }

    private var historyFileURL: URL {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return docDir.appendingPathComponent("mimi_ai_chat_history_v1.json")
    }

    public func clearHistory() {
        messages = []
        try? FileManager.default.removeItem(at: historyFileURL)
    }

    private func saveHistory() {
        let persisted: [PersistedChatMessage] = messages.suffix(100).map { message in
            var texts: [String] = []
            var drafts: [ParsedDraftBill] = []
            for block in message.blocks {
                switch block {
                case .text(let text):
                    texts.append(text)
                case .pendingAnswer:
                    // 等待态不按原样持久化：若 App 在等待中被杀，重开后显示未完成提示而非永久转圈
                    texts.append("（上次问账没有完成，请重新问一次）")
                case .draftBills(let bills):
                    drafts.append(contentsOf: bills)
                case .categoryTable(let expenseRows, let incomeRows, let customNote):
                    var tableText = "标准支出分类如下："
                    for row in expenseRows {
                        tableText += "\n\(row.0)：\(row.1)"
                    }
                    if !incomeRows.isEmpty {
                        tableText += "\n标准收入分类如下："
                        for row in incomeRows {
                            tableText += "\n\(row.0)：\(row.1)"
                        }
                    }
                    if !customNote.isEmpty {
                        tableText += "\n\(customNote)"
                    }
                    texts.append(tableText)
                case .spendingSummary(let title, let amount, let count, let details):
                    texts.append("\(title)\n总支出 \(MimiTheme.formatRM(amount)) · 共 \(count) 笔\n\(details)")
                }
            }
            return PersistedChatMessage(
                isUser: message.isUser,
                text: message.isUser ? message.userText : texts.joined(separator: "\n"),
                drafts: drafts,
                createdAt: message.createdAt
            )
        }
        if let data = try? JSONEncoder().encode(persisted) {
            try? data.write(to: historyFileURL, options: .atomic)
        }
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyFileURL),
              let persisted = try? JSONDecoder().decode([PersistedChatMessage].self, from: data) else {
            return
        }
        messages = persisted.map { item in
            var blocks: [AIChatResponseBlock] = []
            if !item.text.isEmpty {
                blocks.append(.text(item.text))
            }
            if !item.drafts.isEmpty {
                blocks.append(.draftBills(item.drafts))
            }
            return AIChatMessageItem(
                isUser: item.isUser,
                userText: item.isUser ? item.text : "",
                blocks: blocks,
                createdAt: item.createdAt
            )
        }
    }

    // MARK: - Natural Language Parsing Helpers

    private func splitClauseOnAmounts(_ segment: String, now: Date, timeZone: TimeZone) -> [String] {
        let splitPattern = #"(?<![0-9\-/:：年月.])([0-9]+(?:\.[0-9]{1,2})?(?:\s*(?:元|块|令吉))?)(?![0-9年月日号点时分天周杯个碗份次张件人笔:/：%\-])(?=\s+(?!年|月|日|号|点|时|分|天前|AM|PM|am|pm)[^\s0-9\.])"#
        guard let regex = try? NSRegularExpression(pattern: splitPattern) else {
            return [segment]
        }
        let nsRange = NSRange(segment.startIndex..<segment.endIndex, in: segment)
        let matches = regex.matches(in: segment, range: nsRange)
        guard !matches.isEmpty else { return [segment] }

        var clauses: [String] = []
        var clauseStart = segment.startIndex
        let trimSet = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.decimalDigits)
        for match in matches {
            guard let range = Range(match.range, in: segment), range.lowerBound >= clauseStart else {
                continue
            }
            let prefix = String(segment[clauseStart..<range.lowerBound])
            let dateStripped = MimiNaturalLanguageDateParser
                .parse(in: prefix, now: now, timeZone: timeZone)
                .strippedText
            let cleanedPrefix = dateStripped
                .replacingOccurrences(of: #"(?i)\b(?:RM|MYR)\b|[¥$]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: trimSet)
            guard !cleanedPrefix.isEmpty else {
                // Keep leading brand numbers (e.g. "99 Speedmart 18.90") attached to their item.
                continue
            }
            let piece = String(segment[clauseStart..<range.upperBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                clauses.append(piece)
            }
            clauseStart = range.upperBound
        }
        let tail = String(segment[clauseStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            clauses.append(tail)
        }
        return clauses.isEmpty ? [segment] : clauses
    }

    private struct AmountCandidate {
        let value: Double
        let range: Range<String.Index>
        let hasCurrency: Bool
        let isDecimal: Bool
    }

    private func extractAmountMatch(from clause: String) -> (value: Double, range: Range<String.Index>)? {
        let pattern = #"((?:RM|MYR|¥|\$)\s*)?([0-9]+(?:\.[0-9]{1,2})?)(\s*(?:元|块|令吉))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(clause.startIndex..<clause.endIndex, in: clause)
        let matches = regex.matches(in: clause, range: nsRange)
        let excludedPrefixes: Set<Character> = ["-", "/", ":", "："]
        let excludedUnits = ["年", "月", "日", "号", "点", "时", "分", "天", "周", "个", "杯", "碗", "份", "次", "张", "件", "人", "笔", "折", "%", "倍", "岁", "楼", "层", "kg", "g", "ml", "l"]

        var candidates: [AmountCandidate] = []
        for match in matches {
            guard let fullRange = Range(match.range, in: clause),
                  let valRange = Range(match.range(at: 2), in: clause),
                  let val = Double(clause[valRange]) else { continue }
            let hasCurrency = match.range(at: 1).location != NSNotFound || match.range(at: 3).location != NSNotFound
            if !hasCurrency {
                if valRange.lowerBound > clause.startIndex {
                    let prevChar = clause[clause.index(before: valRange.lowerBound)]
                    if excludedPrefixes.contains(prevChar) || (prevChar.isASCII && prevChar.isLetter) {
                        continue
                    }
                }
                let after = clause[valRange.upperBound...]
                if after.first == "-", let second = after.dropFirst().first, second.isASCII && second.isLetter {
                    continue
                }
                let afterTrimmed = after.trimmingCharacters(in: .whitespaces).lowercased()
                if excludedUnits.contains(where: { afterTrimmed.hasPrefix($0) }) {
                    continue
                }
            }
            candidates.append(
                AmountCandidate(
                    value: val,
                    range: fullRange,
                    hasCurrency: hasCurrency,
                    isDecimal: clause[valRange].contains(".")
                )
            )
        }
        if let picked = candidates.last(where: { $0.hasCurrency }) {
            return (picked.value, picked.range)
        }
        if let picked = candidates.last(where: { $0.isDecimal }) {
            return (picked.value, picked.range)
        }
        if let picked = candidates.last {
            return (picked.value, picked.range)
        }
        return nil
    }

    private func detectIncome(in clause: String) -> Bool {
        let lower = clause.lowercased()
        if clause.contains("转给") || clause.contains("还给") || clause.contains("借给") {
            return false
        }
        let incomeKeywords = [
            "工资", "薪水", "发薪", "奖金", "花红", "津贴", "补助",
            "还我", "还钱", "转我", "给我转",
            "收款", "收到", "收入", "到账", "兼职", "副业",
            "报销到账", "退税", "退款", "返现", "cashback",
            "分红", "股息", "利息", "中奖"
        ]
        if incomeKeywords.contains(where: { lower.contains($0) }) {
            return true
        }
        return clause.contains("收") && !clause.contains("手续费") && !clause.contains("收费")
    }

    private func detectAccount(
        in clause: String,
        preferredAccountId: String? = nil,
        preferredAccountName: String? = nil
    ) -> (String?, String) {
        let lower = clause.lowercased()
        if lower.contains("tng") || lower.contains("ewallet") || lower.contains("touch") || lower.contains("一触即通") {
            return ("acc_tng", "TNGewallet")
        }
        if lower.contains("pbb") || lower.contains("大众") || lower.contains("pbbank") || lower.contains("public bank") {
            return ("acc_pbb", "PBBank")
        }
        if lower.contains("cimb") || lower.contains("联昌") {
            return ("acc_cimb", "CIMB")
        }
        if lower.contains("现金") || lower.contains("cash") {
            return ("acc_cash", "现金")
        }
        if let preferredAccountId, let preferredAccountName {
            return (preferredAccountId, preferredAccountName)
        }
        return ("acc_tng", "TNGewallet")
    }

    private func detectCategory(in clause: String, isIncome: Bool) -> (String, String?, String) {
        let lower = clause.lowercased()
        if isIncome {
            if lower.contains("报销") {
                return ("inc_refund", "inc_refund_reimburse", "退款返还-报销")
            }
            if lower.contains("返现") || lower.contains("cashback") {
                return ("inc_refund", "inc_refund_cashback", "退款返还-返现")
            }
            if lower.contains("退税") {
                return ("inc_refund", "inc_refund_tax", "退款返还-退税")
            }
            if lower.contains("退款") {
                return ("inc_refund", nil, "退款返还")
            }
            if lower.contains("还") || lower.contains("转账") || lower.contains("转我") {
                return ("inc_custom_transfer", nil, "别人转账")
            }
            if lower.contains("奖金") || lower.contains("花红") {
                return ("inc_salary", "inc_salary_bonus", "职业收入-绩效奖金")
            }
            if lower.contains("津贴") || lower.contains("补助") {
                return ("inc_salary", "inc_salary_allowance", "职业收入-津贴补助")
            }
            if lower.contains("兼职") || lower.contains("副业") {
                return ("inc_sidejob", nil, "副业兼职")
            }
            if lower.contains("分红") || lower.contains("股息") {
                return ("inc_invest", "inc_invest_dividend", "投资收入-股息分红")
            }
            if lower.contains("利息") {
                return ("inc_invest", "inc_invest_interest", "投资收入-利息")
            }
            if lower.contains("生活费") {
                return ("inc_gift", "inc_gift_living", "礼金收入-生活费")
            }
            if lower.contains("二手") {
                return ("inc_other", "inc_other_secondhand", "其他收入-二手买卖")
            }
            if lower.contains("中奖") || lower.contains("好运") {
                return ("inc_other", "inc_other_lucky", "其他收入-好运收入")
            }
            return ("inc_salary", nil, "职业收入")
        }

        if lower.contains("车贷") {
            return ("exp_custom_carloan", nil, "车贷")
        }
        if lower.contains("家用") {
            return ("exp_custom_home", nil, "家用")
        }
        if lower.contains("加油") || lower.contains("打油") || lower.contains("充电") || lower.contains("shell") || lower.contains("petronas") || lower.contains("petron") || lower.contains("caltex") || lower.contains("bhp") {
            return ("exp_transport", "exp_trans_fuel", "交通-加油充电")
        }
        if lower.contains("打车") || lower.contains("滴滴") || lower.contains("grab") || lower.contains("taxi") {
            return ("exp_transport", "exp_trans_taxi", "交通-打车叫车")
        }
        if lower.contains("mrt") || lower.contains("lrt") || lower.contains("ktm") || lower.contains("monorail") || lower.contains("地铁") || lower.contains("轻快铁") || lower.contains("巴士") || lower.contains("公交") || lower.contains("rapid") {
            return ("exp_transport", "exp_trans_public", "交通-公共交通")
        }
        if lower.contains("过路") || lower.contains("toll") || lower.contains("rfid") || lower.contains("smarttag") || lower.contains("停车") || lower.contains("parking") || lower.contains("泊车") {
            return ("exp_transport", "exp_trans_parking", "交通-过路停车")
        }
        if lower.contains("高铁") || lower.contains("火车") || lower.contains("机票") || lower.contains("airasia") || lower.contains("klia") || lower.contains("ets") {
            return ("exp_transport", "exp_trans_intercity", "交通-城际出行")
        }
        if lower.contains("洗车") || lower.contains("保养") || lower.contains("修车") || lower.contains("养车") {
            return ("exp_transport", "exp_trans_carcare", "交通-养车")
        }
        if lower.contains("房租") || lower.contains("租金") || lower.contains("房贷") {
            return ("exp_housing", "exp_house_rent", "住房-房租房贷")
        }
        if lower.contains("水电") || lower.contains("电费") || lower.contains("水费") || lower.contains("tnb") || lower.contains("煤气") {
            return ("exp_housing", "exp_house_utility", "住房-物业水电")
        }
        if lower.contains("话费") || lower.contains("网费") || lower.contains("宽带") || lower.contains("unifi") || lower.contains("maxis") || lower.contains("celcom") || lower.contains("digi") || lower.contains("umobile") || lower.contains("hotlink") {
            return ("exp_housing", "exp_house_telecom", "住房-话费网费")
        }
        if lower.contains("物业") {
            return ("exp_housing", "exp_house_mgmt", "住房-物业管理费")
        }
        if lower.contains("麻将") || lower.contains("电影") || lower.contains("游戏") || lower.contains("娱乐") || lower.contains("ktv") || lower.contains("剧本杀") {
            return ("exp_entertainment", "exp_ent_offline", "休闲娱乐-线下娱乐")
        }
        if lower.contains("健身") || lower.contains("运动") || lower.contains("羽毛球") || lower.contains("游泳") || lower.contains("gym") {
            return ("exp_entertainment", "exp_ent_sport", "休闲娱乐-运动健身")
        }
        if lower.contains("会员") || lower.contains("订阅") || lower.contains("netflix") || lower.contains("spotify") || lower.contains("icloud") || lower.contains("youtube") {
            return ("exp_entertainment", "exp_ent_sub", "休闲娱乐-订阅会员")
        }
        if lower.contains("旅游") || lower.contains("度假") || lower.contains("酒店") || lower.contains("民宿") || lower.contains("airbnb") || lower.contains("agoda") {
            return ("exp_entertainment", "exp_ent_travel", "休闲娱乐-旅游度假")
        }
        if lower.contains("看病") || lower.contains("买药") || lower.contains("诊所") || lower.contains("医院") || lower.contains("klinik") || lower.contains("pharmacy") || lower.contains("panadol") {
            return ("exp_medical", "exp_med_doctor", "医疗健康-看病买药")
        }
        if lower.contains("牙医") || lower.contains("洗牙") || lower.contains("看牙") {
            return ("exp_medical", "exp_med_dental", "医疗健康-医美齿科")
        }
        if lower.contains("宠物") || lower.contains("猫粮") || lower.contains("狗粮") || lower.contains("猫砂") {
            return ("exp_pet", "exp_pet_food", "宠物-宠物食品")
        }
        if lower.contains("奶粉") || lower.contains("尿布") || lower.contains("纸尿裤") || lower.contains("母婴") {
            return ("exp_baby", "exp_baby_supply", "母婴-母婴用品")
        }
        if lower.contains("图书") || lower.contains("文具") || lower.contains("买书") {
            return ("exp_study", "exp_study_stationery", "学习办公-图书文具")
        }
        if lower.contains("学费") || lower.contains("培训") {
            return ("exp_study", "exp_study_tuition", "学习办公-教育学费")
        }
        if lower.contains("还款") || lower.contains("还钱") || lower.contains("还给") {
            return ("exp_transfer_social", "exp_social_repay", "资金往来-还款")
        }
        if lower.contains("转账") || lower.contains("转给") || lower.contains("红包") || lower.contains("人情") || lower.contains("送礼") || lower.contains("借给") {
            return ("exp_transfer_social", "exp_social_gift", "资金往来-人情往来")
        }
        if lower.contains("保险") {
            return ("exp_insurance", nil, "保险")
        }
        if lower.contains("奶茶") || lower.contains("饮品") || lower.contains("茶") || lower.contains("teh") || lower.contains("chagee") || lower.contains("霸王茶姬") || lower.contains("tealive") || lower.contains("mixue") || lower.contains("蜜雪") {
            return ("exp_food", "exp_food_drink", "餐饮-饮品")
        }
        if lower.contains("咖啡") || lower.contains("coffee") || lower.contains("starbucks") || lower.contains("zus") || lower.contains("luckin") || lower.contains("瑞幸") || lower.contains("kopi") {
            return ("exp_food", "exp_food_coffee", "餐饮-咖啡")
        }
        if lower.contains("甜品") || lower.contains("零食") || lower.contains("egg") || lower.contains("蛋糕") || lower.contains("面包") || lower.contains("冰淇淋") {
            return ("exp_food", "exp_food_snack", "餐饮-零食甜品")
        }
        if lower.contains("外卖") || lower.contains("grabfood") || lower.contains("foodpanda") {
            return ("exp_food", "exp_food_takeout", "餐饮-外卖外带")
        }
        if lower.contains("酒吧") || lower.contains("喝酒") || lower.contains("啤酒") {
            return ("exp_food", "exp_food_bar", "餐饮-酒吧酒水")
        }
        if lower.contains("买菜") || lower.contains("食材") || lower.contains("巴刹") || lower.contains("pasar") {
            return ("exp_food", "exp_food_ingredient", "餐饮-做饭食材")
        }
        if lower.contains("护肤") || lower.contains("化妆") || lower.contains("面膜") || lower.contains("防晒") {
            return ("exp_shopping", "exp_shop_beauty", "购物-美妆护肤")
        }
        if lower.contains("衣服") || lower.contains("裤子") || lower.contains("鞋子") || lower.contains("uniqlo") || lower.contains("zara") {
            return ("exp_shopping", "exp_shop_clothes", "购物-服饰鞋包")
        }
        if lower.contains("数码") || lower.contains("耳机") || lower.contains("充电线") || lower.contains("键盘") || lower.contains("手机壳") {
            return ("exp_shopping", "exp_shop_digital", "购物-数码电器")
        }
        if lower.contains("购物") || lower.contains("超市") || lower.contains("99 speedmart") || lower.contains("jaya grocer") || lower.contains("aeon") || lower.contains("watsons") || lower.contains("mr diy") || (lower.contains("买") && !lower.contains("吃")) {
            return ("exp_shopping", "exp_shop_daily", "购物-生活用品")
        }
        return ("exp_food", "exp_food_restaurant", "餐饮-餐厅")
    }

    private func cleanClauseNote(_ clause: String, removingAmountRange: Range<String.Index>? = nil) -> String {
        var text = clause
        if let removingAmountRange {
            text.removeSubrange(removingAmountRange)
        } else {
            text = text.replacingOccurrences(
                of: #"(?:RM|MYR|¥|\$)?\s*[0-9]+(?:\.[0-9]{1,2})?(?:元|块|令吉)?"#,
                with: "",
                options: .regularExpression
            )
        }
        let cleaned = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "，,；;。、")))
        if cleaned.hasPrefix("的") && cleaned.count > 1 {
            return String(cleaned.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }
}
