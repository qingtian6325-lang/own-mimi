import Foundation
import SwiftUI
#if canImport(AppIntents)
import AppIntents
#endif
#if canImport(UIKit)
import UIKit
#endif

public struct ShortcutExecutionOutcome: Equatable, Sendable {
    public let transactionId: UUID
    public let draft: ParsedDraftBill
    public let didOpenAppForEditing: Bool

    public init(transactionId: UUID, draft: ParsedDraftBill, didOpenAppForEditing: Bool) {
        self.transactionId = transactionId
        self.draft = draft
        self.didOpenAppForEditing = didOpenAppForEditing
    }
}

// MARK: - Scan Confirmation Follow-Up Decision (v1.1.3)

/// 确认卡交互结束后的动作决策（纯逻辑，可单测）。
///
/// v1.1.3 起确认卡的系统按钮对改名为 View / Got it（与 Kapi 一致）：
/// 点「Got it」（accept）时 requestConfirmation 正常返回，随后落盘结束；
/// 点「View」（deny）或下滑关卡时，系统以同一种「取消」信号抛错回来，
/// 两者无法区分——按产品决策统一当作「去修改」：不落正式账，
/// 改为打开 App 到这笔的编辑页。其他错误则作废这笔，安静结束。
public enum ScanConfirmationFollowUp: Equatable, Sendable {
    /// 点了「View」或下滑关卡：打开 App 改这笔（暂存转未确认记录）。
    case openEditor
    /// 其他错误：作废暂存，不落盘、不打开 App。
    case discard

    public static func followUp(for error: Error) -> ScanConfirmationFollowUp {
        isCancellation(error) ? .openEditor : .discard
    }

    /// 取消类错误的判定：requestConfirmation 被拒绝/取消时按官方约定抛
    /// CancellationError；个别系统路径可能换一种错误类型回传，故再按
    /// 错误类型名含 "cancel" 兜底（只认类型名，避免把无关 NSError 误判）。
    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return String(describing: type(of: error)).localizedCaseInsensitiveContains("cancel")
    }
}

// MARK: - Scan Choice Plan (v1.1.4, iOS 26 requestChoice 探针)

/// iOS 26 选项卡的两个选项。文案与 Kapi 完全一致（英文 View / Got it）。
/// 选项的 Style 只有 .default / .destructive / .cancel 三种，没有主次样式，
/// 故两个选项都用 .default，颜色与排版由系统决定（探针要验的正是这一点）。
public enum ScanChoicePick: Equatable, Sendable {
    case view
    case gotIt
}

/// 选项卡的文案常量与「选择 → 后续动作」映射（纯逻辑，可单测）。
/// perform 里的选项构造用与这里相同的字面量，两处必须保持一致。
public enum ScanChoicePlan {
    public static let viewOptionTitle = "View"
    public static let gotItOptionTitle = "Got it"
    /// requestChoice 的 dialog 提示文案：与之前卡内 ✓ 行同一句。
    /// 选项卡的 view 只放纯账单卡（不含这一行），保证这句话只出现一次。
    public static let promptText = "已识别记录以上信息，打开「咪咪记账」查看更多"

    /// 选 View：不在 perform 里消费暂存，由 opensIntent 的后续 Intent
    /// 消费暂存并打开 App 到编辑页。选 Got it：不开 App。
    public static func opensEditor(for pick: ScanChoicePick) -> Bool {
        pick == .view
    }

    /// 选 Got it：先在 perform 里把暂存正式落盘。选 View：不在 perform 落盘。
    public static func finalizesInPerform(for pick: ScanChoicePick) -> Bool {
        pick == .gotIt
    }
}

@MainActor
public enum ShortcutActionCoordinator {
    /// 「添加专属指令」一键导入链接（iCloud 快捷指令分享链接，形如 https://www.icloud.com/shortcuts/xxxx）。
    /// 该链接只能由登录 iCloud 的设备在「快捷指令」App 内通过「共享 → 拷贝 iCloud 链接」生成，
    /// 服务器端无法伪造；在用户提供链接之前保持 nil，指南页的「添加专属指令」按钮将展开手动搭建教程。
    public static let shortcutInstallURL: String? = nil

    /// 把识别草稿构建为 TransactionItem（含收据图保存），但不落盘。
    public static func makeTransaction(from draft: ParsedDraftBill, in store: MimiStore, isConfirmed: Bool) -> TransactionItem {
        var attachments: [String] = []
        if let raw = draft.rawImageData {
            let filename = store.saveReceiptImage(data: raw)
            attachments.append(filename)
        }
        return TransactionItem(
            type: draft.type,
            categoryPath: draft.categoryPath,
            iconName: draft.iconName,
            amount: draft.amount,
            accountName: draft.accountName,
            targetAccountName: draft.targetAccountName,
            note: draft.note,
            receiptImageLabels: attachments,
            date: draft.date,
            isConfirmed: isConfirmed
        )
    }

    public static func recordRecognizedDraft(_ draft: ParsedDraftBill, in store: MimiStore) -> TransactionItem {
        let tx = makeTransaction(from: draft, in: store, isConfirmed: true)
        store.addTransaction(tx)
        return tx
    }

    /// 确认型流程第一步（v1.1.2）：识别结果先暂存（isConfirmed=false），
    /// 不落盘、不计入余额/列表，等用户在系统确认卡上做决定。
    public static func stageRecognizedDraft(_ draft: ParsedDraftBill, in store: MimiStore) -> TransactionItem {
        let tx = makeTransaction(from: draft, in: store, isConfirmed: false)
        store.stagePendingScan(tx)
        return tx
    }

    /// 确认型流程第二步（用户点系统「确认」后）：消费暂存并以正式账单落盘。
    /// 暂存已被「修改」路径消费时返回 nil，绝不重复记账。
    @discardableResult
    public static func finalizePendingScan(id: UUID, in store: MimiStore) -> TransactionItem? {
        guard let staged = store.consumePendingScan(id: id) else { return nil }
        var confirmed = staged
        confirmed.isConfirmed = true
        store.addTransaction(confirmed)
        return confirmed
    }

    /// 「修改 (View)」路径：消费暂存，以未确认状态转入正式记录并定位到 App 内编辑页，
    /// 用户在 App 里改完保存即完成这笔。暂存已被消费但正式记录已存在时（例如重复点击、
    /// 或确认路径已落盘），只重新定位到编辑页，不重复记账。
    @discardableResult
    public static func consumePendingScanForEdit(id: UUID, in store: MimiStore) -> TransactionItem? {
        if let staged = store.consumePendingScan(id: id) {
            store.addTransaction(staged)
            _ = markForInAppModification(transactionId: staged.id, in: store)
            return staged
        }
        if let existing = store.transactions.first(where: { $0.id == id }) {
            _ = markForInAppModification(transactionId: existing.id, in: store)
            return existing
        }
        return nil
    }

    public static func markForInAppModification(transactionId: UUID, in store: MimiStore) -> URL {
        store.pendingEditTransactionId = transactionId
        return URL(string: "mimimoney://edit-bill?id=\(transactionId.uuidString)")!
    }

    public static func handleIncomingURL(_ url: URL, in store: MimiStore) -> Bool {
        guard url.scheme?.lowercased() == "mimimoney" else { return false }
        if url.host == "edit-bill",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let idString = components.queryItems?.first(where: { $0.name == "id" })?.value,
           let uuid = UUID(uuidString: idString) {
            store.pendingEditTransactionId = uuid
            return true
        }
        if url.host == "quick-scan" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let amountParam = components?.queryItems?.first(where: { $0.name == "amount" })?.value
            let noteParam = components?.queryItems?.first(where: { $0.name == "note" || $0.name == "merchant" })?.value
            let accountParam = components?.queryItems?.first(where: { $0.name == "account" })?.value

            var draft: ParsedDraftBill?

            if let amtStr = amountParam, let amt = Double(amtStr), amt > 0 {
                let note = noteParam ?? "快捷记账"
                let acc = accountParam ?? "TNGewallet"
                let detected = DefaultCatalog.resolveCategoryIds(from: note, type: .expense)
                draft = ParsedDraftBill(
                    type: .expense,
                    amount: amt,
                    primaryCategoryId: detected.primaryId,
                    subCategoryId: detected.subId,
                    categoryDisplayName: detected.primaryId,
                    accountId: DefaultCatalog.resolveAccountId(from: acc),
                    accountDisplayName: acc,
                    merchantOrNote: note,
                    occurredAt: Date()
                )
            }
            // v1.2.1：识别已改纯 AI（Gemini），URL 入口不再做文字/剪贴板解析；
            // 只有带 amount 参数的快速记账会生成记录，其余情况走下方打开手动记账页。

            if let recognized = draft {
                let saved = recordRecognizedDraft(recognized, in: store)
                store.pendingShortcutSnippetBill = saved
                return true
            } else {
                store.isRecordSheetPresented = true
                return true
            }
        }
        return false
    }

    public static func openShortcutsApp() {
        #if canImport(UIKit)
        if let url = URL(string: "shortcuts://") {
            UIApplication.shared.open(url)
        }
        #endif
    }

}

// MARK: - Screenshot Result Snippet View (1:1 Match with IMG_2294.PNG)

public struct ScreenshotResultSnippetView: View {
    public let transaction: TransactionItem
    public var onModifyTapped: (() -> Void)?
    public var onConfirmTapped: (() -> Void)?
    public var onCloseTapped: (() -> Void)?

    public init(
        transaction: TransactionItem,
        onModifyTapped: (() -> Void)? = nil,
        onConfirmTapped: (() -> Void)? = nil,
        onCloseTapped: (() -> Void)? = nil
    ) {
        self.transaction = transaction
        self.onModifyTapped = onModifyTapped
        self.onConfirmTapped = onConfirmTapped
        self.onCloseTapped = onCloseTapped
    }

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: transaction.date)
    }

    private var signedAmountText: String {
        let prefix = transaction.type == .expense ? "-RM" : "+RM"
        return String(format: "%@%.2f", prefix, transaction.amount)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // White recognized bill card inside blue-white gradient popup (IMG_2294 & user feedback)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    MimiStickerIconView(iconName: transaction.iconName, size: 28)

                    Text(transaction.categoryPath)
                        .mimiFont(15, weight: .bold)
                        .foregroundColor(MimiTheme.textPrimary)

                    Spacer()

                    Text(signedAmountText)
                        .mimiFont(17, weight: .bold, design: .rounded)
                        .foregroundColor(
                            transaction.type == .expense ? MimiTheme.expenseBlue : MimiTheme.incomeOrange
                        )

                    if let onClose = onCloseTapped {
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .mimiFont(16)
                                .foregroundColor(MimiTheme.textMuted.opacity(0.7))
                        }
                        .mimiPressable()
                    }
                }

                HStack(spacing: 6) {
                    Text(transaction.accountName)
                        .mimiFont(11, weight: .medium)
                        .foregroundColor(MimiTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(MimiTheme.fillSubtle)
                        )

                    if !transaction.note.isEmpty {
                        Text(transaction.note)
                            .mimiFont(11, weight: .medium)
                            .foregroundColor(MimiTheme.textSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(MimiTheme.fillSubtle)
                            )
                    }

                    Spacer()

                    Text(formattedTimestamp)
                        .mimiFont(11, weight: .regular)
                        .foregroundColor(MimiTheme.textMuted)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            )

            // Recognition confirmation caption
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .mimiFont(13)
                    .foregroundColor(MimiTheme.expenseBlue)
                Text("已识别记录以上信息，打开「咪咪记账」查看更多")
                    .mimiFont(12, weight: .medium)
                    .foregroundColor(MimiTheme.textSecondary)
            }

            // In-app snippet always uses callbacks so confirm/edit actually save / open detail.
            // App Intent buttons are only for Shortcuts system confirmation cards.
            fallbackTwoButtons
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [MimiTheme.tintBlueSoft, MimiTheme.background],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 6)
    }

    private var fallbackTwoButtons: some View {
        HStack(spacing: 12) {
            Button {
                onModifyTapped?()
            } label: {
                Text("修改 (View)")
                    .mimiFont(14, weight: .semibold)
                    .foregroundColor(MimiTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        Capsule().fill(MimiTheme.fillSubtle)
                    )
            }
            .mimiPressable()

            Button {
                onConfirmTapped?()
            } label: {
                Text("确认 (Got it)")
                    .mimiFont(14, weight: .semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        Capsule().fill(MimiTheme.expenseBlue)
                    )
            }
            .mimiPressable()
        }
    }
}

// MARK: - Scan Confirmation Card View (确认型呈现专用，v1.1.2)

/// 确认卡卡面：与 ScreenshotResultSnippetView 上半部长相一致（分类图标+分类-二级、
/// 金额、账户 chip、备注 chip、时间、✓ 识别提示一行）。v1.1.3 起卡内不放任何
/// 自制按钮——卡面下方只有系统渲染的一对按钮 View / Got it（requestConfirmation
/// 的 actionName 改名而来，与 Kapi 一致）：Got it = 确认入账，View = 打开 App
/// 改这笔（经 perform 的 catch 分支接成「转未确认记录＋前台打开 App」，见 ScanScreenshotIntent）。
public struct ScanConfirmationCardView: View {
    public let transaction: TransactionItem

    public init(transaction: TransactionItem) {
        self.transaction = transaction
    }

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: transaction.date)
    }

    private var signedAmountText: String {
        let prefix = transaction.type == .expense ? "-RM" : "+RM"
        return String(format: "%@%.2f", prefix, transaction.amount)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    MimiStickerIconView(iconName: transaction.iconName, size: 28)

                    Text(transaction.categoryPath)
                        .mimiFont(15, weight: .bold)
                        .foregroundColor(MimiTheme.textPrimary)

                    Spacer()

                    Text(signedAmountText)
                        .mimiFont(17, weight: .bold, design: .rounded)
                        .foregroundColor(
                            transaction.type == .expense ? MimiTheme.expenseBlue : MimiTheme.incomeOrange
                        )
                }

                HStack(spacing: 6) {
                    Text(transaction.accountName)
                        .mimiFont(11, weight: .medium)
                        .foregroundColor(MimiTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(MimiTheme.fillSubtle)
                        )

                    if !transaction.note.isEmpty {
                        Text(transaction.note)
                            .mimiFont(11, weight: .medium)
                            .foregroundColor(MimiTheme.textSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(MimiTheme.fillSubtle)
                            )
                    }

                    Spacer()

                    Text(formattedTimestamp)
                        .mimiFont(11, weight: .regular)
                        .foregroundColor(MimiTheme.textMuted)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            )

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .mimiFont(13)
                    .foregroundColor(MimiTheme.expenseBlue)
                Text("已识别记录以上信息，打开「咪咪记账」查看更多")
                    .mimiFont(12, weight: .medium)
                    .foregroundColor(MimiTheme.textSecondary)
            }

            // v1.1.3：卡内不再有任何自制按钮。View / Got it 由系统在卡面
            // 下方成对渲染（见 requestScanConfirmation 的 actionName 改名）。
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [MimiTheme.tintBlueSoft, MimiTheme.background],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 6)
    }
}

// MARK: - Scan Choice Card View (iOS 26 requestChoice 专用，v1.1.4)

/// 选项卡的纯账单卡：与 ScanConfirmationCardView 的账单部分一致，但不含
/// ✓ 提示行（那句话改由 requestChoice 的 dialog 呈现，只出现一次）、
/// 不含任何按钮（选项由系统在卡外渲染）。外层渐变与圆角沿用前几版卡面，
/// 让探针的观感变量只剩「系统如何排选项」这一项。
public struct ScanChoiceCardView: View {
    public let transaction: TransactionItem

    public init(transaction: TransactionItem) {
        self.transaction = transaction
    }

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: transaction.date)
    }

    private var signedAmountText: String {
        let prefix = transaction.type == .expense ? "-RM" : "+RM"
        return String(format: "%@%.2f", prefix, transaction.amount)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                MimiStickerIconView(iconName: transaction.iconName, size: 28)

                Text(transaction.categoryPath)
                    .mimiFont(15, weight: .bold)
                    .foregroundColor(MimiTheme.textPrimary)

                Spacer()

                Text(signedAmountText)
                    .mimiFont(17, weight: .bold, design: .rounded)
                    .foregroundColor(
                        transaction.type == .expense ? MimiTheme.expenseBlue : MimiTheme.incomeOrange
                    )
            }

            HStack(spacing: 6) {
                Text(transaction.accountName)
                    .mimiFont(11, weight: .medium)
                    .foregroundColor(MimiTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(MimiTheme.fillSubtle)
                    )

                if !transaction.note.isEmpty {
                    Text(transaction.note)
                        .mimiFont(11, weight: .medium)
                        .foregroundColor(MimiTheme.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(MimiTheme.fillSubtle)
                        )
                }

                Spacer()

                Text(formattedTimestamp)
                    .mimiFont(11, weight: .regular)
                    .foregroundColor(MimiTheme.textMuted)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
        .padding(16)
        .background(
            LinearGradient(
                colors: [MimiTheme.tintBlueSoft, MimiTheme.background],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 6)
    }
}

// MARK: - iOS AppIntents Integration (Shortcuts Screenshot Bookkeeping)

#if canImport(AppIntents)
@available(iOS 16.0, macOS 13.0, *)
public struct OpenBillForEditIntent: AppIntent {
    public static var title: LocalizedStringResource = "修改账单 (View)"
    public static var description = IntentDescription("打开咪咪记账并跳转到该笔账单详情编辑页")
    public static var openAppWhenRun: Bool = true
    public static var isDiscoverable: Bool = false

    @Parameter(title: "账单ID")
    public var transactionIdString: String

    public init() {
        self.transactionIdString = ""
    }

    public init(transactionId: UUID) {
        self.transactionIdString = transactionId.uuidString
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        if let uuid = UUID(uuidString: transactionIdString) {
            _ = ShortcutActionCoordinator.markForInAppModification(
                transactionId: uuid,
                in: MimiStore.shared
            )
        }
        return .result()
    }
}

@available(iOS 16.0, macOS 13.0, *)
public struct ConfirmBillIntent: AppIntent {
    public static var title: LocalizedStringResource = "确认记账 (Got it)"
    public static var description = IntentDescription("确认截图识别的账单并直接完成记账，无需进入App")
    public static var openAppWhenRun: Bool = false
    public static var isDiscoverable: Bool = false

    @Parameter(title: "账单ID")
    public var transactionIdString: String

    public init() {
        self.transactionIdString = ""
    }

    public init(transactionId: UUID) {
        self.transactionIdString = transactionId.uuidString
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        MimiStore.shared.pendingShortcutSnippetBill = nil
        return .result()
    }
}

@available(iOS 16.0, macOS 13.0, *)
public struct OpenPendingScanForEditIntent: AppIntent {
    public static var title: LocalizedStringResource = "修改待确认账单 (View)"
    public static var description = IntentDescription("把确认卡上的待确认识别账单转入咪咪记账并打开编辑页")
    public static var openAppWhenRun: Bool = true
    public static var isDiscoverable: Bool = false

    @Parameter(title: "账单ID")
    public var transactionIdString: String

    public init() {
        self.transactionIdString = ""
    }

    public init(transactionId: UUID) {
        self.transactionIdString = transactionId.uuidString
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        if let uuid = UUID(uuidString: transactionIdString) {
            _ = ShortcutActionCoordinator.consumePendingScanForEdit(
                id: uuid,
                in: MimiStore.shared
            )
        }
        return .result()
    }
}

/// 「识别账单」的统一后续 Intent（v1.1.4）：ScanScreenshotIntent 的全部出口都以
/// opensIntent 指向本 Intent——单一目标类型是硬约束：同一 perform 里混用普通
/// .result() 或不同目标的 opensIntent 都会触发 #OpaqueTypeInference
/// （v1.1.3 两次 CI 实证，run 42970310739 的报错即此），故两种后续收敛到
/// 本 Intent、用 opensEditor 参数区分：
/// - opensEditor=false：无操作占位。Got it 已在 perform 内落盘、旧系统路径的
///   收尾也已在 perform 内完成，本 Intent 执行后不打开 App、无任何副作用，
///   捷徑流程静默结束回原 App。
/// - opensEditor=true（iOS 26 选项卡选了 View）：消费暂存→转未确认记录→
///   定位编辑页，再靠 .foreground(.dynamic) 的 continueInForeground
///   (alwaysConfirm: false) 把 App 带到前台——用户刚点过 View、交互新鲜，
///   预期免确认直达（WWDC25-275 的 recency 规则）；前台失败也不丢账，
///   记录已安全转未确认并定位，手动打开 App 同样直达编辑页。
@available(iOS 16.0, macOS 13.0, *)
public struct ScanChoiceFollowUpIntent: AppIntent {
    public static var title: LocalizedStringResource = "识别账单后续"
    public static var description = IntentDescription("完成截图记账的收尾：无操作结束，或按需打开咪咪记账到待确认账单的编辑页")
    public static var openAppWhenRun: Bool = false
    public static var isDiscoverable: Bool = false

    @Parameter(title: "打开编辑页")
    public var opensEditor: Bool

    @Parameter(title: "账单ID")
    public var transactionIdString: String

    public init() {
        self.opensEditor = false
        self.transactionIdString = ""
    }

    public init(opensEditor: Bool, transactionId: UUID) {
        self.opensEditor = opensEditor
        self.transactionIdString = transactionId.uuidString
    }

    @available(iOS 26.0, macOS 26.0, *)
    public static var supportedModes: IntentModes {
        [.background, .foreground(.dynamic)]
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        guard opensEditor, let uuid = UUID(uuidString: transactionIdString) else {
            return .result()
        }
        _ = ShortcutActionCoordinator.consumePendingScanForEdit(id: uuid, in: MimiStore.shared)
        if #available(iOS 26.0, macOS 26.0, *) {
            // 打开被拒/失败就安静结束：记录已转为未确认并标记定位，
            // 用户手动打开 App 也会直达这笔的编辑页。
            try? await continueInForeground(alwaysConfirm: false)
        }
        return .result()
    }
}

/// iOS 26 确认型呈现的卡片驱动 Intent：按账单 id 从暂存区（或已落盘记录）取账单，
/// 渲染 ScanConfirmationCardView。系统在交互后可能重跑本 Intent 刷新卡面，
/// 所以取不到暂存时回退到正式记录，保证卡面不空白。
@available(iOS 26.0, macOS 26.0, *)
public struct ScanConfirmationSnippetIntent: SnippetIntent {
    public static var title: LocalizedStringResource = "确认识别账单"
    public static var description = IntentDescription("展示待确认的识别账单卡片")
    public static var isDiscoverable: Bool = false

    @Parameter(title: "账单ID")
    public var transactionIdString: String

    public init() {
        self.transactionIdString = ""
    }

    public init(transactionId: UUID) {
        self.transactionIdString = transactionId.uuidString
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ShowsSnippetView {
        let store = MimiStore.shared
        let transaction = UUID(uuidString: transactionIdString).flatMap { id in
            store.pendingScan(id: id) ?? store.transactions.first(where: { $0.id == id })
        }
        if let transaction {
            return .result(view: AnyView(ScanConfirmationCardView(transaction: transaction)))
        }
        return .result(view: AnyView(
            Text("这笔识别结果已处理")
                .mimiFont(13, weight: .medium)
                .foregroundColor(MimiTheme.textSecondary)
                .padding(16)
        ))
    }
}

@available(iOS 16.0, macOS 13.0, *)
public struct ScanScreenshotIntent: AppIntent {
    public static var title: LocalizedStringResource = "识别账单"
    public static var description = IntentDescription("识别账单截图并录入金额、商户或转账收款人与扣款账户，弹出确认与修改卡片")
    public static var openAppWhenRun: Bool = false

    @Parameter(title: "内容")
    public var content: IntentFile?

    @Parameter(title: "类型", default: 2)
    public var type: Int?

    @Parameter(title: "版本", default: "1.3.19")
    public var version: String?

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & OpensIntent {
        let store = MimiStore.shared
        // v1.2.1：识别改纯 AI（Gemini），彻底移除 OCR，不再有任何兜底凑数。
        // 识别失败直接抛 ReceiptRecognitionFailure（LocalizedError），捷徑会
        // 把失败原因弹给用户看；失败时不暂存、不落账、不弹识别卡。
        let screenshotData: Data?
        if let file = content {
            screenshotData = file.data
        } else {
            #if canImport(UIKit)
            if let image = UIPasteboard.general.image, let pngData = image.pngData() {
                screenshotData = pngData
            } else {
                screenshotData = nil
            }
            #else
            screenshotData = nil
            #endif
        }
        guard let imageData = screenshotData else {
            GeminiSettings.recordCallStatus(success: false, message: ReceiptRecognitionFailure.noImage.statusText)
            throw ReceiptRecognitionFailure.noImage
        }
        let recognition = try await SmartReceiptRecognizer.recognize(imageData: imageData)
        let draft = recognition.draft
        let amountIsSuspicious = recognition.isSuspiciousAmount
        // 呈现分层（v1.1.4）：
        // - iOS 26+：requestChoice 选项卡探针（见 performScanChoice）。前几版已
        //   证实：结果型 snippet 底部必带系统 Done、确认型必带 Cancel＋主钮一对
        //   且 Cancel 删不掉（HIG 解剖图＋ConfirmationActionName 官方 API），
        //   requestChoice 是唯一未被官方排除的呈现——卡面＋两个完全自定的选项，
        //   选中后回到 perform 继续。它的实际长相只能真机定案。
        // - iOS 18–25 / 17：保持 v1.1.2/1.1.3 的确认型流程，行为一行不改：
        //   识别结果先暂存（不落盘）→ requestConfirmation 弹确认卡（按钮对
        //   改名为 View / Got it）→ 点 Got it 才正式落盘；点 View/下滑走
        //   catch 分支转未确认记录并前台打开 App；其他错误作废暂存。
        //
        // 全部出口统一返回 IntentResult & OpensIntent，且 opensIntent 只指向
        // 单一目标 ScanChoiceFollowUpIntent（用 opensEditor 参数区分动作）：
        // 同一 perform 里混用普通 .result()、或指向不同 Intent 的 opensIntent，
        // 都会让不透明返回类型对不上而编译失败（#OpaqueTypeInference，
        // v1.1.3 两次 CI 实证）。旧系统路径的收尾动作仍在 perform 内完成，
        // 返回的 opensIntent 只是无操作占位，行为与 v1.1.3 的空 .result() 等价。
        let staged = ShortcutActionCoordinator.stageRecognizedDraft(draft, in: store)
        if amountIsSuspicious {
            // 金额合理性拦截：金额 <=0、离谱大额或与状态栏电量百分比同值等明显误读，
            // 只进未确认口径 — 暂存转未确认记录等用户在 App 里核对修改，
            // 不走正常入账呈现（不弹选项卡/确认卡）。
            _ = ShortcutActionCoordinator.consumePendingScanForEdit(id: staged.id, in: store)
            return .result(opensIntent: ScanChoiceFollowUpIntent(opensEditor: false, transactionId: staged.id))
        }
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await performScanChoice(staged: staged, store: store)
        }
        do {
            try await requestScanConfirmation(for: staged)
        } catch {
            switch ScanConfirmationFollowUp.followUp(for: error) {
            case .openEditor:
                _ = ShortcutActionCoordinator.consumePendingScanForEdit(id: staged.id, in: store)
                if #available(iOS 17.0, macOS 14.0, *) {
                    // 前台打开失败（系统拒绝/用户取消）也不要抛错：记录已安全
                    // 转为未确认并标记定位，用户手动打开 App 也会直达编辑页。
                    try? await requestToContinueInForeground(
                        IntentDialog("打开「咪咪记账」修改这笔账单")
                    ) { }
                }
                return .result(opensIntent: ScanChoiceFollowUpIntent(opensEditor: false, transactionId: staged.id))
            case .discard:
                store.discardPendingScan(id: staged.id)
                return .result(opensIntent: ScanChoiceFollowUpIntent(opensEditor: false, transactionId: staged.id))
            }
        }
        _ = ShortcutActionCoordinator.finalizePendingScan(id: staged.id, in: store)
        return .result(opensIntent: ScanChoiceFollowUpIntent(opensEditor: false, transactionId: staged.id))
    }

    /// iOS 26 选项卡呈现（v1.1.4 探针）：requestChoice 弹「纯账单卡（view)＋
    /// 提示文案（dialog)」与两个系统渲染的自定选项 View / Got it，选中后
    /// 回到这里继续。选项不加 .cancel：取消/下滑时 requestChoice 抛错，
    /// catch 里先作废暂存、再以同一返回形状安静收尾——官方指引是不要
    /// catch 取消错误，这里 catch 的唯一目的是在终止前作废暂存，随后
    /// 返回的仍是无呈现、无落盘、不开 App 的结果，与直接终止等价。
    /// - 选 View：不在 perform 里消费暂存，opensIntent 交给
    ///   ScanChoiceFollowUpIntent 消费暂存并打开 App 到编辑页。
    /// - 选 Got it：先在 perform 里正式落盘，再 opensIntent 一个无操作
    ///   后续，静默结束回原 App。
    /// requestChoice 返回的必是给出的两个选项之一（Equatable 比对），
    /// 非 View 即 Got it。
    @available(iOS 26.0, macOS 26.0, *)
    @MainActor
    private func performScanChoice(staged: TransactionItem, store: MimiStore) async throws -> some IntentResult & OpensIntent {
        // 选项文案与 ScanChoicePlan 的常量是同一组字面量，两处保持一致。
        // Style 只有 .default / .destructive / .cancel，没有主样式，
        // 故两个选项都不带 style（默认 .default），排版与颜色由系统决定。
        let viewOption = IntentChoiceOption(title: "View")
        let gotItOption = IntentChoiceOption(title: "Got it")
        let choice: IntentChoiceOption
        do {
            choice = try await requestChoice(
                between: [viewOption, gotItOption],
                dialog: "\(ScanChoicePlan.promptText)",
                view: ScanChoiceCardView(transaction: staged)
            )
        } catch {
            store.discardPendingScan(id: staged.id)
            return .result(opensIntent: ScanChoiceFollowUpIntent(opensEditor: false, transactionId: staged.id))
        }
        let pick: ScanChoicePick = (choice == viewOption) ? .view : .gotIt
        if ScanChoicePlan.finalizesInPerform(for: pick) {
            _ = ShortcutActionCoordinator.finalizePendingScan(id: staged.id, in: store)
        }
        return .result(opensIntent: ScanChoiceFollowUpIntent(
            opensEditor: ScanChoicePlan.opensEditor(for: pick),
            transactionId: staged.id
        ))
    }

    /// 按系统版本分层弹确认卡，按钮文案统一改名为 View / Got it（与 Kapi 一致）：
    /// iOS 26+ 用 SnippetIntent 驱动的互动确认卡；
    /// iOS 18–25 用带 content 视图的确认（同一套 ConfirmationActionName.custom）；
    /// iOS 17 的旧确认 API 只接受预置文案（.log，对应 Log / Cancel），无法改名，
    /// 功能不变——这是该层的既有限制。
    /// 注（v1.1.4）：perform 在 iOS 26+ 已改走 requestChoice 选项卡、不再调用
    /// 本方法，故 iOS 26 分层在现行调用链上不会触发，保留仅为分层完整与回退便利；
    /// iOS 18–25 / 17 两层的行为与 v1.1.3 完全一致。
    @MainActor
    private func requestScanConfirmation(for transaction: TransactionItem) async throws {
        if #available(iOS 26.0, macOS 26.0, *) {
            try await requestConfirmation(
                actionName: .custom(acceptLabel: "Got it", acceptAlternatives: [], denyLabel: "View", denyAlternatives: []),
                snippetIntent: ScanConfirmationSnippetIntent(transactionId: transaction.id)
            )
        } else if #available(iOS 18.0, macOS 15.0, *) {
            try await requestConfirmation(
                actionName: .custom(acceptLabel: "Got it", acceptAlternatives: [], denyLabel: "View", denyAlternatives: []),
                dialog: nil, showDialogAsPrompt: false
            ) {
                ScanConfirmationCardView(transaction: transaction)
            }
        } else {
            let amountText = String(
                format: "%@RM%.2f",
                transaction.type == .expense ? "-" : "+",
                transaction.amount
            )
            // Pre-macOS-15 / iOS-17 fallback: older overload (confirmationActionName).
            // The actionName: API needs macOS 15+ and cannot live in this else branch
            // while Package.swift still targets macOS(.v14) for host unit tests.
            try await requestConfirmation(
                result: .result(dialog: "确认记账：\(transaction.categoryPath) \(amountText)（\(transaction.accountName)）？"),
                confirmationActionName: .log
            )
        }
    }
}

/// 前台继续能力（v1.1.3）：「识别账单」在确认卡被点「View」/下滑取消后，
/// 靠这个协议请求系统把 App 带到前台打开编辑页。协议本身 iOS 16.4 起可用，
/// 故以带可用性标注的 extension 形式声明一致性，不抬高 Intent 本体的
/// @available(iOS 16.0)（部署目标 17.0，实际运行不受影响）。
@available(iOS 16.4, macOS 13.3, *)
extension ScanScreenshotIntent: ForegroundContinuableIntent {}

@available(iOS 16.0, macOS 13.0, *)
public struct MimiAppShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanScreenshotIntent(),
            phrases: [
                "用\(.applicationName)识别账单",
                "在\(.applicationName)识别账单",
                "用\(.applicationName)截图记账"
            ],
            shortTitle: "识别账单",
            systemImageName: "camera.viewfinder"
        )
    }
}
#else
public struct OpenBillForEditIntent: Sendable {
    public static let openAppWhenRun: Bool = true
    public let transactionIdString: String
    public init(transactionId: UUID) { self.transactionIdString = transactionId.uuidString }
}
public struct ConfirmBillIntent: Sendable {
    public static let openAppWhenRun: Bool = false
    public let transactionIdString: String
    public init(transactionId: UUID) { self.transactionIdString = transactionId.uuidString }
}
public struct OpenPendingScanForEditIntent: Sendable {
    public static let openAppWhenRun: Bool = true
    public let transactionIdString: String
    public init(transactionId: UUID) { self.transactionIdString = transactionId.uuidString }
}
public struct ScanChoiceFollowUpIntent: Sendable {
    public static let openAppWhenRun: Bool = false
    public let opensEditor: Bool
    public let transactionIdString: String
    public init(opensEditor: Bool, transactionId: UUID) {
        self.opensEditor = opensEditor
        self.transactionIdString = transactionId.uuidString
    }
}
public struct ScanScreenshotIntent: Sendable {
    public init() {}
}
public struct MimiAppShortcutsProvider: Sendable {
    public init() {}
}
#endif
