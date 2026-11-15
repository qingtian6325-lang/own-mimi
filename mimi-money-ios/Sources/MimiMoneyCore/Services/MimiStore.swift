import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

public struct PersistedAppState: Codable, Sendable {
    public var ledgers: [LedgerItem]
    public var currentLedgerId: String
    public var accounts: [AccountItem]
    public var transactions: [TransactionItem]
    public var auditLogs: [AccountAuditLog]
    public var expenseCategories: [CategoryGroup]
    public var incomeCategories: [CategoryGroup]
    public var tags: [String]
    /// 月统计/预算账期起始日（1…28）。1 = 自然月。
    public var monthStartDay: Int
    /// 是否已完成新手指南。旧存档缺字段时按「已完成」迁移，避免老用户被强制引导。
    public var hasCompletedOnboarding: Bool

    public init(
        ledgers: [LedgerItem],
        currentLedgerId: String,
        accounts: [AccountItem],
        transactions: [TransactionItem],
        auditLogs: [AccountAuditLog],
        expenseCategories: [CategoryGroup],
        incomeCategories: [CategoryGroup],
        tags: [String],
        monthStartDay: Int = 1,
        hasCompletedOnboarding: Bool = false
    ) {
        self.ledgers = ledgers
        self.currentLedgerId = currentLedgerId
        self.accounts = accounts
        self.transactions = transactions
        self.auditLogs = auditLogs
        self.expenseCategories = expenseCategories
        self.incomeCategories = incomeCategories
        self.tags = tags
        self.monthStartDay = BillingPeriodEngine.clampedStartDay(monthStartDay)
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    private enum CodingKeys: String, CodingKey {
        case ledgers, currentLedgerId, accounts, transactions, auditLogs
        case expenseCategories, incomeCategories, tags, monthStartDay, hasCompletedOnboarding
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ledgers = try c.decode([LedgerItem].self, forKey: .ledgers)
        currentLedgerId = try c.decode(String.self, forKey: .currentLedgerId)
        accounts = try c.decode([AccountItem].self, forKey: .accounts)
        transactions = try c.decode([TransactionItem].self, forKey: .transactions)
        auditLogs = try c.decode([AccountAuditLog].self, forKey: .auditLogs)
        expenseCategories = try c.decode([CategoryGroup].self, forKey: .expenseCategories)
        incomeCategories = try c.decode([CategoryGroup].self, forKey: .incomeCategories)
        tags = try c.decode([String].self, forKey: .tags)
        monthStartDay = BillingPeriodEngine.clampedStartDay(try c.decodeIfPresent(Int.self, forKey: .monthStartDay) ?? 1)
        // Missing key → existing install: treat as completed
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? true
    }
}

@MainActor
public final class MimiStore: ObservableObject {
    public static let shared = MimiStore()

    @Published public var ledgers: [LedgerItem]
    @Published public var currentLedgerId: String {
        didSet { cachedGroupedTransactions = nil }
    }
    @Published public var accounts: [AccountItem]
    @Published public var transactions: [TransactionItem] {
        didSet { cachedGroupedTransactions = nil }
    }
    @Published public var auditLogs: [AccountAuditLog]
    @Published public var expenseCategories: [CategoryGroup]
    @Published public var incomeCategories: [CategoryGroup]
    @Published public var tags: [String]
    @Published public var pendingEditTransactionId: UUID?
    @Published public var pendingShortcutSnippetBill: TransactionItem?
    @Published public var pendingScanTransactions: [TransactionItem] = []
    @Published public var isRecordSheetPresented: Bool = false
    @Published public var hideAmounts: Bool = false
    @Published public var reimbursableAmount: Double = 0.00
    @Published public var userNickname: String = "jinghao"
    @Published public var hapticsEnabled: Bool = true
    @Published public var scheduledTransactions: [ScheduledTransactionItem] = []
    /// 月账期起始日 1…28（1 = 自然月 1 号）
    @Published public var monthStartDay: Int = 1
    @Published public var hasCompletedOnboarding: Bool = false

    private let inMemory: Bool
    private let storageURL: URL
    private let pendingScansURL: URL
    private static var receiptMemoryCache: [String: Data] = [:]
    private var cachedGroupedTransactions: [(date: Date, items: [TransactionItem])]?

    // MARK: - Receipt Image Persistence
    public var receiptsDirectoryURL: URL {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let receiptsURL = docDir.appendingPathComponent("Receipts", isDirectory: true)
        if !FileManager.default.fileExists(atPath: receiptsURL.path) {
            try? FileManager.default.createDirectory(at: receiptsURL, withIntermediateDirectories: true)
        }
        return receiptsURL
    }

    /// Saves receipt image with cross-sandbox resilience.
    /// If image data is reasonably sized (<= 350KB), stores inline base64 string
    /// so AppIntents / Shortcuts running in external extension sandboxes NEVER lose
    /// access to the image when viewed in the main app.
    public func saveReceiptImage(data: Data) -> String {
        var finalData = data
        #if canImport(UIKit)
        if data.count > 180_000, let uiImg = UIImage(data: data) {
            // Resize and compress for lightweight persistence
            let maxDim: CGFloat = 1200
            let size = uiImg.size
            if size.width > maxDim || size.height > maxDim {
                let ratio = min(maxDim / size.width, maxDim / size.height)
                let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
                let renderer = UIGraphicsImageRenderer(size: newSize)
                let resized = renderer.image { _ in
                    uiImg.draw(in: CGRect(origin: .zero, size: newSize))
                }
                if let compressed = resized.jpegData(compressionQuality: 0.65) {
                    finalData = compressed
                }
            } else if let compressed = uiImg.jpegData(compressionQuality: 0.70) {
                finalData = compressed
            }
        }
        #endif

        let filename = "receipt_\(UUID().uuidString.prefix(12)).jpg"
        let fileURL = receiptsDirectoryURL.appendingPathComponent(filename)
        try? finalData.write(to: fileURL, options: .atomic)
        Self.receiptMemoryCache[filename] = finalData

        // Also write to temporary and caches directory as fallback
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        try? finalData.write(to: tempURL, options: .atomic)

        // For guaranteed cross-sandbox / shortcut persistence, return base64 if <= 350KB
        if finalData.count <= 350_000 {
            let base64String = "base64:\(finalData.base64EncodedString())"
            Self.receiptMemoryCache[base64String] = finalData
            return base64String
        }

        return filename
    }

    /// Robust loader for receipt images: supports base64 inline, memory cache,
    /// documents folder, temporary directories, caches, and app group containers.
    public func loadReceiptImageData(filename: String) -> Data? {
        let clean = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        // 1. Direct Base64 prefix
        if clean.hasPrefix("base64:") {
            let base64Payload = String(clean.dropFirst(7))
            if let decoded = Data(base64Encoded: base64Payload, options: .ignoreUnknownCharacters) {
                return decoded
            }
        }
        if clean.hasPrefix("data:image/") && clean.contains(";base64,") {
            let components = clean.components(separatedBy: ";base64,")
            if components.count == 2, let decoded = Data(base64Encoded: components[1], options: .ignoreUnknownCharacters) {
                return decoded
            }
        }

        // 2. Memory cache
        if let cached = Self.receiptMemoryCache[clean] {
            return cached
        }

        // 3. Absolute path on disk (must actually exist on filesystem)
        if (clean.hasPrefix("/") || clean.contains(":\\")) && FileManager.default.fileExists(atPath: clean) {
            if let diskData = try? Data(contentsOf: URL(fileURLWithPath: clean)) {
                Self.receiptMemoryCache[clean] = diskData
                return diskData
            }
        }

        // 4. Standard receipts directory (must actually exist)
        let standardURL = receiptsDirectoryURL.appendingPathComponent(clean)
        if FileManager.default.fileExists(atPath: standardURL.path),
           let diskData = try? Data(contentsOf: standardURL) {
            Self.receiptMemoryCache[clean] = diskData
            return diskData
        }

        // 5. Look up by lastPathComponent in documents, temp, caches, app group if it looks like a filename
        let lastComponent = URL(fileURLWithPath: clean).lastPathComponent
        if lastComponent.contains(".") {
            let candidateURLs = [
                receiptsDirectoryURL.appendingPathComponent(lastComponent),
                URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(lastComponent),
                FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(lastComponent),
                FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(lastComponent),
                FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.mimi.money")?.appendingPathComponent("Receipts/\(lastComponent)")
            ].compactMap { $0 }

            for cand in candidateURLs {
                if FileManager.default.fileExists(atPath: cand.path),
                   let diskData = try? Data(contentsOf: cand) {
                    Self.receiptMemoryCache[clean] = diskData
                    return diskData
                }
            }
        }

        // 6. Base64 fallback (supports bare Base64 including standard JPEG /9j/ headers)
        if let bareDecoded = Data(base64Encoded: clean, options: .ignoreUnknownCharacters), !bareDecoded.isEmpty {
            Self.receiptMemoryCache[clean] = bareDecoded
            return bareDecoded
        }

        return nil
    }

    public func deleteReceiptImage(filename: String) {
        let clean = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        Self.receiptMemoryCache.removeValue(forKey: clean)
        if !clean.hasPrefix("base64:") {
            let fileURL = clean.hasPrefix("/") ? URL(fileURLWithPath: clean) : receiptsDirectoryURL.appendingPathComponent(clean)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    public init(inMemory: Bool = false) {
        self.inMemory = inMemory
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.storageURL = docDir.appendingPathComponent("mimi_money_state_v2.json")
        self.pendingScansURL = docDir.appendingPathComponent("mimi_pending_scans_v1.json")

        if !inMemory,
           let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode(PersistedAppState.self, from: data) {
            self.ledgers = decoded.ledgers
            self.currentLedgerId = decoded.currentLedgerId
            self.accounts = decoded.accounts
            self.transactions = decoded.transactions
            self.auditLogs = decoded.auditLogs
            self.expenseCategories = decoded.expenseCategories
            self.incomeCategories = decoded.incomeCategories
            self.tags = decoded.tags
            self.monthStartDay = decoded.monthStartDay
            self.hasCompletedOnboarding = decoded.hasCompletedOnboarding
        } else if inMemory {
            // Unit test in-memory store uses deterministic test dataset
            let initial = Self.makeDemoAppState()
            self.ledgers = initial.ledgers
            self.currentLedgerId = initial.currentLedgerId
            self.accounts = initial.accounts
            self.transactions = initial.transactions
            self.auditLogs = initial.auditLogs
            self.expenseCategories = initial.expenseCategories
            self.incomeCategories = initial.incomeCategories
            self.tags = initial.tags
            self.monthStartDay = initial.monthStartDay
            self.hasCompletedOnboarding = initial.hasCompletedOnboarding
            self.reimbursableAmount = 1000.00
        } else {
            // Production App default: completely empty transactions, audit logs, and 0.00 account balances
            let empty = Self.makeCleanEmptyAppState()
            self.ledgers = empty.ledgers
            self.currentLedgerId = empty.currentLedgerId
            self.accounts = empty.accounts
            self.transactions = empty.transactions
            self.auditLogs = empty.auditLogs
            self.expenseCategories = empty.expenseCategories
            self.incomeCategories = empty.incomeCategories
            self.tags = empty.tags
            self.monthStartDay = empty.monthStartDay
            self.hasCompletedOnboarding = empty.hasCompletedOnboarding
            self.reimbursableAmount = 0.00
        }
        if !inMemory,
           let data = try? Data(contentsOf: pendingScansURL),
           let decoded = try? JSONDecoder().decode([TransactionItem].self, from: data) {
            self.pendingScanTransactions = decoded
        }
        sanitizeImportedSharedStringArtifacts()
        DefaultCatalog.syncLiveAccounts(accounts)
        recalculateAllAccountBalances()
    }

    public var currentLedger: LedgerItem {
        get {
            ledgers.first(where: { $0.id == currentLedgerId }) ?? DefaultCatalog.defaultLedger()
        }
        set {
            if let idx = ledgers.firstIndex(where: { $0.id == newValue.id }) {
                ledgers[idx] = newValue
                saveState()
            }
        }
    }

    public func addTransaction(_ item: TransactionItem, at loggedAt: Date = Date()) {
        transactions.insert(item, at: 0)
        transactions.sort(by: { $0.date > $1.date })
        applyBalanceEffect(for: item, multiplier: 1.0)
        recalculateAllAccountBalances()
        appendAuditLog(for: item, action: .created, loggedAt: loggedAt)
        saveState()
    }

    // MARK: - Pending Shortcut Scan Staging （确认型识别流程的待确认暂存区）
    //
    // v1.1.2 起「识别账单」改为确认型呈现：识别结果先暂存到这里
    // （isConfirmed=false），不进 transactions，因此不影响余额、列表与统计；
    // 用户在系统确认卡上点「确认」后才由 finalize 路径正式落盘，点「修改」
    // 则由 edit 路径以未确认状态转入正式记录并进 App 编辑，取消/下滑则永不落盘。
    // 每个暂存项只能被消费一次（consume 后即删除），保证绝不重复记账。
    // 暂存单独落盘到 mimi_pending_scans_v1.json（不并入 PersistedAppState，
    // 避免旧存档 Codable 解码兼容风险），因为捷徑 Intent 与 App 可能运行在
    // 不同进程，暂存必须持久化才能跨进程接力。

    public func stagePendingScan(_ item: TransactionItem) {
        if let idx = pendingScanTransactions.firstIndex(where: { $0.id == item.id }) {
            pendingScanTransactions[idx] = item
        } else {
            pendingScanTransactions.append(item)
        }
        // 只保留最近 20 条，防取消确认后残留的孤儿暂存无限累积
        if pendingScanTransactions.count > 20 {
            pendingScanTransactions.removeFirst(pendingScanTransactions.count - 20)
        }
        savePendingScans()
    }

    public func pendingScan(id: UUID) -> TransactionItem? {
        pendingScanTransactions.first(where: { $0.id == id })
    }

    /// 原子消费一个暂存项：取出并删除。同一 id 第二次调用必然返回 nil（单次消费/幂等）。
    @discardableResult
    public func consumePendingScan(id: UUID) -> TransactionItem? {
        guard let idx = pendingScanTransactions.firstIndex(where: { $0.id == id }) else { return nil }
        let item = pendingScanTransactions.remove(at: idx)
        savePendingScans()
        return item
    }

    public func discardPendingScan(id: UUID) {
        pendingScanTransactions.removeAll(where: { $0.id == id })
        savePendingScans()
    }

    private func savePendingScans() {
        guard !inMemory else { return }
        if let data = try? JSONEncoder().encode(pendingScanTransactions) {
            try? data.write(to: pendingScansURL, options: .atomic)
        }
    }

    public func updateTransaction(_ updated: TransactionItem, at loggedAt: Date = Date()) {
        guard let idx = transactions.firstIndex(where: { $0.id == updated.id }) else { return }
        let old = transactions[idx]
        applyBalanceEffect(for: old, multiplier: -1.0)
        transactions[idx] = updated
        transactions.sort(by: { $0.date > $1.date })
        applyBalanceEffect(for: updated, multiplier: 1.0)
        recalculateAllAccountBalances()
        appendAuditLog(for: updated, action: .updated, loggedAt: loggedAt)
        saveState()
    }

    public func deleteTransaction(id: UUID, at loggedAt: Date = Date()) {
        guard let idx = transactions.firstIndex(where: { $0.id == id }) else { return }
        let removed = transactions.remove(at: idx)
        // Incremental balance only — full reconcile + disk write deferred so swipe-delete stays snappy.
        applyBalanceEffect(for: removed, multiplier: -1.0)
        appendAuditLog(for: removed, action: .deleted, loggedAt: loggedAt)
        schedulePersistAfterUI()
    }

    /// Let SwiftUI commit list removal / press feedback first, then reconcile + persist.
    private func schedulePersistAfterUI() {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.recalculateAllAccountBalances()
            self.saveState()
        }
    }

    public func recalculateAllAccountBalances() {
        for idx in accounts.indices {
            let delta = accountTransactionDelta(accountId: accounts[idx].id)
            accounts[idx].balance = ((accounts[idx].initialBalance + delta) * 100.0).rounded() / 100.0
        }
    }

    public func accountTransactionDelta(accountId: String) -> Double {
        let acc = accounts.first(where: { $0.id == accountId })
        let accName = acc?.name ?? accountId
        var delta: Double = 0.0
        for tx in transactions {
            let net = max(0.0, tx.amount - tx.discountAmount - tx.refundAmount)
            let txSrcId = tx.accountId ?? DefaultCatalog.resolveAccountId(from: tx.accountName)
            let isSrc = txSrcId == accountId || tx.accountId == accountId || tx.accountName == accName
            let txDstId = tx.targetAccountId ?? (tx.targetAccountName.map { DefaultCatalog.resolveAccountId(from: $0) } ?? nil)
            let isDst = txDstId == accountId || tx.targetAccountId == accountId || tx.targetAccountName == accName

            if tx.type == .expense && isSrc {
                delta -= net
            } else if tx.type == .income && isSrc {
                delta += net
            } else if tx.type == .transfer {
                if isSrc {
                    delta -= net
                }
                if isDst {
                    delta += net
                }
            }
        }
        return ((delta * 100.0).rounded()) / 100.0
    }

    public func setAccountInitialBalance(accountId: String, initialBalance: Double) {
        guard let idx = accounts.firstIndex(where: { $0.id == accountId }) else { return }
        let roundedInit = (initialBalance * 100.0).rounded() / 100.0
        accounts[idx].initialBalance = roundedInit
        let delta = accountTransactionDelta(accountId: accountId)
        let newCurrent = ((roundedInit + delta) * 100.0).rounded() / 100.0
        accounts[idx].balance = newCurrent

        let log = AccountAuditLog(
            accountId: accountId,
            action: .updated,
            transactionType: .income,
            categoryTitle: "设定期初资金 | \(accounts[idx].name)",
            note: "设定记账前起始资金为 RM\(String(format: "%.2f", roundedInit))",
            amount: roundedInit,
            balanceAfter: newCurrent,
            billDate: Date(),
            loggedAt: Date()
        )
        auditLogs.insert(log, at: 0)
        saveState()
    }

    public func setAccountInitialBalance(accountName: String, initialBalance: Double) {
        if let match = accounts.first(where: { $0.name == accountName || $0.id == accountName }) {
            setAccountInitialBalance(accountId: match.id, initialBalance: initialBalance)
        }
    }

    public func updateAccountBalance(accountId: String, newBalance: Double) {
        guard let idx = accounts.firstIndex(where: { $0.id == accountId }) else { return }
        let oldBalance = accounts[idx].balance
        let roundedNew = (newBalance * 100.0).rounded() / 100.0
        accounts[idx].balance = roundedNew
        let delta = roundedNew - oldBalance
        let transDelta = accountTransactionDelta(accountId: accountId)
        accounts[idx].initialBalance = ((roundedNew - transDelta) * 100.0).rounded() / 100.0
        let log = AccountAuditLog(
            accountId: accountId,
            action: .updated,
            transactionType: delta >= 0 ? .income : .expense,
            categoryTitle: "修改余额 | \(accounts[idx].name)",
            note: "手动修改账户余额",
            amount: abs(delta),
            balanceAfter: roundedNew,
            billDate: Date(),
            loggedAt: Date()
        )
        auditLogs.insert(log, at: 0)
        saveState()
    }

    public func updateAccountBalance(accountName: String, newBalance: Double) {
        if let match = accounts.first(where: { $0.name == accountName || $0.id == accountName }) {
            updateAccountBalance(accountId: match.id, newBalance: newBalance)
        }
    }

    public func addAccount(_ account: AccountItem) {
        accounts.append(account)
        DefaultCatalog.syncLiveAccounts(accounts)
        saveState()
    }

    public func updateAccount(_ account: AccountItem) {
        guard let idx = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        var next = account
        // Metadata edit must not clobber the running ledger balance.
        next.balance = accounts[idx].balance
        next.initialBalance = accounts[idx].initialBalance
        if next.isDefaultAccount {
            for i in accounts.indices where accounts[i].id != next.id {
                accounts[i].isDefaultAccount = false
            }
        }
        accounts[idx] = next
        DefaultCatalog.syncLiveAccounts(accounts)
        saveState()
    }

    public func deleteAccount(accountId: String) {
        guard accounts.count > 1 else { return }
        accounts.removeAll(where: { $0.id == accountId })
        saveState()
    }

    public func addPrimaryCategory(name: String, type: TransactionType, iconName: String, useFirstCharIcon: Bool) {
        let newGroup = CategoryGroup(
            id: "custom_\(UUID().uuidString.prefix(8))",
            name: name,
            type: type,
            iconName: iconName,
            useFirstCharIcon: useFirstCharIcon,
            isCustom: true,
            subCategories: [],
            sortOrder: (type == .expense ? expenseCategories.count : incomeCategories.count)
        )
        if type == .expense {
            expenseCategories.append(newGroup)
        } else {
            incomeCategories.append(newGroup)
        }
        saveState()
    }

    public func addPrimaryCategory(type: TransactionType, name: String, iconName: String, useFirstCharIcon: Bool) {
        addPrimaryCategory(name: name, type: type, iconName: iconName, useFirstCharIcon: useFirstCharIcon)
    }

    public func addSubCategory(to groupId: String, name: String, iconName: String) {
        if let idx = expenseCategories.firstIndex(where: { $0.id == groupId }) {
            let sub = SubCategory(
                id: "sub_\(UUID().uuidString.prefix(8))",
                name: name,
                iconName: iconName,
                sortOrder: expenseCategories[idx].subCategories.count
            )
            expenseCategories[idx].subCategories.append(sub)
            saveState()
            return
        }
        if let idx = incomeCategories.firstIndex(where: { $0.id == groupId }) {
            let sub = SubCategory(
                id: "sub_\(UUID().uuidString.prefix(8))",
                name: name,
                iconName: iconName,
                sortOrder: incomeCategories[idx].subCategories.count
            )
            incomeCategories[idx].subCategories.append(sub)
            saveState()
        }
    }

    public func addSubcategory(
        toGroupId: String,
        type: TransactionType,
        name: String,
        iconName: String,
        useFirstCharIcon: Bool
    ) {
        addSubCategory(to: toGroupId, name: name, iconName: iconName)
    }

    public func renamePrimaryCategory(id: String, type: TransactionType, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if type == .expense, let idx = expenseCategories.firstIndex(where: { $0.id == id }) {
            expenseCategories[idx].name = trimmed
            saveState()
        } else if type == .income, let idx = incomeCategories.firstIndex(where: { $0.id == id }) {
            incomeCategories[idx].name = trimmed
            saveState()
        }
    }

    public func updatePrimaryCategoryIcon(id: String, type: TransactionType, iconName: String, useFirstCharIcon: Bool) {
        if type == .expense, let idx = expenseCategories.firstIndex(where: { $0.id == id }) {
            expenseCategories[idx].iconName = iconName
            expenseCategories[idx].useFirstCharIcon = useFirstCharIcon
            saveState()
        } else if type == .income, let idx = incomeCategories.firstIndex(where: { $0.id == id }) {
            incomeCategories[idx].iconName = iconName
            incomeCategories[idx].useFirstCharIcon = useFirstCharIcon
            saveState()
        }
    }

    public func deletePrimaryCategory(id: String, type: TransactionType) {
        if type == .expense {
            guard expenseCategories.count > 1 else { return }
            expenseCategories.removeAll(where: { $0.id == id })
        } else {
            guard incomeCategories.count > 1 else { return }
            incomeCategories.removeAll(where: { $0.id == id })
        }
        saveState()
    }

    public func renameSubcategory(groupId: String, subId: String, type: TransactionType, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        func rename(in groups: inout [CategoryGroup]) {
            guard let gIdx = groups.firstIndex(where: { $0.id == groupId }),
                  let sIdx = groups[gIdx].subCategories.firstIndex(where: { $0.id == subId }) else { return }
            groups[gIdx].subCategories[sIdx].name = trimmed
        }
        if type == .expense {
            rename(in: &expenseCategories)
        } else {
            rename(in: &incomeCategories)
        }
        saveState()
    }

    public func deleteSubcategory(groupId: String, subId: String, type: TransactionType) {
        func remove(in groups: inout [CategoryGroup]) {
            guard let gIdx = groups.firstIndex(where: { $0.id == groupId }) else { return }
            groups[gIdx].subCategories.removeAll(where: { $0.id == subId })
        }
        if type == .expense {
            remove(in: &expenseCategories)
        } else {
            remove(in: &incomeCategories)
        }
        saveState()
    }

    public func moveSubcategory(groupId: String, type: TransactionType, from fromIndex: Int, to toIndex: Int) {
        func move(in groups: inout [CategoryGroup]) {
            guard let gIdx = groups.firstIndex(where: { $0.id == groupId }) else { return }
            var subs = groups[gIdx].subCategories
            guard fromIndex >= 0, fromIndex < subs.count,
                  toIndex >= 0, toIndex < subs.count,
                  fromIndex != toIndex else { return }
            let item = subs.remove(at: fromIndex)
            subs.insert(item, at: toIndex)
            for i in subs.indices { subs[i].sortOrder = i }
            groups[gIdx].subCategories = subs
        }
        if type == .expense {
            move(in: &expenseCategories)
        } else {
            move(in: &incomeCategories)
        }
        saveState()
    }

    public func movePrimaryCategory(type: TransactionType, from fromIndex: Int, to toIndex: Int) {
        func move(in groups: inout [CategoryGroup]) {
            guard fromIndex >= 0, fromIndex < groups.count,
                  toIndex >= 0, toIndex < groups.count,
                  fromIndex != toIndex else { return }
            let item = groups.remove(at: fromIndex)
            groups.insert(item, at: toIndex)
            for i in groups.indices { groups[i].sortOrder = i }
        }
        if type == .expense {
            move(in: &expenseCategories)
        } else {
            move(in: &incomeCategories)
        }
        saveState()
    }

    public func clearPendingReimbursementTag(on transactionId: UUID) {
        guard let idx = transactions.firstIndex(where: { $0.id == transactionId }) else { return }
        var tx = transactions[idx]
        tx.tags.removeAll { tag in
            let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            return t == "待报销" || t == "报销"
        }
        updateTransaction(tx)
    }

    public var monthlyBudgetTotal: Double {
        get { currentLedger.monthlyBudget }
        set {
            var ledger = currentLedger
            ledger.monthlyBudget = newValue
            currentLedger = ledger
        }
    }

    // MARK: - Ledger Management Functions
    public func addLedger(name: String, currency: CurrencyCode = .myr, monthlyBudget: Double = 3000.0) {
        let newLedger = LedgerItem(
            id: "ledger_\(UUID().uuidString.prefix(8))",
            name: name,
            currency: currency,
            monthlyBudget: monthlyBudget,
            categoryBudgets: DefaultCatalog.defaultLedger().categoryBudgets
        )
        ledgers.append(newLedger)
        currentLedgerId = newLedger.id
        saveState()
    }

    public func renameLedger(id: String, newName: String) {
        guard let idx = ledgers.firstIndex(where: { $0.id == id }) else { return }
        ledgers[idx].name = newName
        saveState()
    }

    public func updateLedgerBudget(id: String, newBudget: Double) {
        guard let idx = ledgers.firstIndex(where: { $0.id == id }) else { return }
        ledgers[idx].monthlyBudget = max(0.0, newBudget)
        saveState()
    }

    public func deleteLedger(id: String) {
        guard ledgers.count > 1 else { return }
        ledgers.removeAll(where: { $0.id == id })
        if currentLedgerId == id {
            currentLedgerId = ledgers.first?.id ?? "ledger_main"
        }
        saveState()
    }

    public func switchLedger(id: String) {
        if ledgers.contains(where: { $0.id == id }) {
            currentLedgerId = id
            saveState()
        }
    }

    // MARK: - Tag Management Functions
    public func addTag(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && !tags.contains(trimmed) else { return }
        tags.append(trimmed)
        saveState()
    }

    public func deleteTag(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        tags.removeAll(where: { $0 == name || $0 == trimmed })
        for idx in transactions.indices {
            transactions[idx].tags.removeAll(where: { $0 == name || $0 == trimmed })
        }
        saveState()
    }

    public func renameTag(oldName: String, newName: String) {
        let oldTrimmed = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTrimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldTrimmed.isEmpty, !newTrimmed.isEmpty, oldTrimmed != newTrimmed else { return }
        if let idx = tags.firstIndex(where: { $0 == oldName || $0 == oldTrimmed }) {
            if tags.contains(newTrimmed) {
                tags.remove(at: idx)
            } else {
                tags[idx] = newTrimmed
            }
        } else if !tags.contains(newTrimmed) {
            tags.append(newTrimmed)
        }
        for idx in transactions.indices {
            guard transactions[idx].tags.contains(where: { $0 == oldName || $0 == oldTrimmed }) else { continue }
            var updated: [String] = []
            for t in transactions[idx].tags {
                let candidate = (t == oldName || t == oldTrimmed) ? newTrimmed : t
                if !updated.contains(candidate) {
                    updated.append(candidate)
                }
            }
            transactions[idx].tags = updated
        }
        saveState()
    }

    /// Cleans stray sharedStrings table index "18" injected by earlier XLSX imports on empty cells,
    /// and ensures any custom non-internal tags on transactions are visible in `tags`.
    public func sanitizeImportedSharedStringArtifacts() {
        var didMutate = false
        if tags.contains("18") {
            tags.removeAll(where: { $0 == "18" })
            didMutate = true
        }
        for idx in transactions.indices {
            let beforeCount = transactions[idx].tags.count
            transactions[idx].tags.removeAll { tag in
                let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed == "18"
            }
            if transactions[idx].tags.count != beforeCount {
                didMutate = true
            }
            if transactions[idx].note.trimmingCharacters(in: .whitespacesAndNewlines) == "18" {
                transactions[idx].note = ""
                didMutate = true
            }
            for tag in transactions[idx].tags {
                let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed != "待报销", !tags.contains(trimmed) else { continue }
                tags.append(trimmed)
                didMutate = true
            }
        }
        if didMutate {
            saveState()
        }
    }

    public func transactions(forTag tag: String) -> [TransactionItem] {
        transactions.filter { $0.tags.contains(tag) }
    }

    // MARK: - Scheduled Bookkeeping Functions
    public func addScheduledTransaction(_ item: ScheduledTransactionItem) {
        scheduledTransactions.append(item)
        saveState()
    }

    public func deleteScheduledTransaction(id: UUID) {
        scheduledTransactions.removeAll(where: { $0.id == id })
        saveState()
    }

    public func toggleScheduledTransaction(id: UUID) {
        guard let idx = scheduledTransactions.firstIndex(where: { $0.id == id }) else { return }
        scheduledTransactions[idx].isEnabled.toggle()
        saveState()
    }

    public func executeScheduledTransactionNow(id: UUID) {
        guard let item = scheduledTransactions.first(where: { $0.id == id }) else { return }
        let tx = TransactionItem(
            ledgerId: currentLedgerId,
            type: item.type,
            amount: item.amount,
            currency: currentLedger.currency,
            primaryCategoryId: item.categoryPath,
            accountId: DefaultCatalog.resolveAccountId(from: item.accountName),
            note: "【定时入账】\(item.title)"
        )
        addTransaction(tx)
    }

    // MARK: - User Settings
    public func setNickname(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            userNickname = trimmed
            saveState()
        }
    }

    public func monthlyBudgetRemaining(year: Int, month: Int) -> Double {
        max(0.0, monthlyBudgetTotal - monthlyExpenseTotal(year: year, month: month))
    }

    public func setMonthStartDay(_ day: Int) {
        monthStartDay = BillingPeriodEngine.clampedStartDay(day)
        saveState()
    }

    public func completeOnboarding() {
        hasCompletedOnboarding = true
        saveState()
    }

    public func reopenOnboarding() {
        hasCompletedOnboarding = false
        saveState()
    }

    public func currentBillingPeriod(now: Date = Date()) -> BillingPeriod {
        BillingPeriodEngine.period(containing: now, startDay: monthStartDay)
    }

    public func expenseTotal(in period: BillingPeriod) -> Double {
        transactions.reduce(0.0) { acc, tx in
            guard tx.ledgerId == currentLedgerId,
                  tx.includeInStats,
                  tx.type == .expense,
                  period.contains(tx.date) else { return acc }
            return acc + max(0.0, tx.amount - tx.discountAmount - tx.refundAmount)
        }
    }

    public func incomeTotal(in period: BillingPeriod) -> Double {
        transactions.reduce(0.0) { acc, tx in
            guard tx.ledgerId == currentLedgerId,
                  tx.includeInStats,
                  tx.type == .income,
                  period.contains(tx.date) else { return acc }
            return acc + tx.amount
        }
    }

    public func budgetRemaining(in period: BillingPeriod) -> Double {
        max(0.0, monthlyBudgetTotal - expenseTotal(in: period))
    }

    public func categorySpent(for categoryName: String, in period: BillingPeriod) -> Double {
        transactions.reduce(0.0) { acc, tx in
            guard tx.ledgerId == currentLedgerId,
                  tx.includeInStats,
                  tx.type == .expense,
                  period.contains(tx.date) else { return acc }
            let primaryName = tx.categoryPath.components(separatedBy: "-").first ?? tx.categoryPath
            guard primaryName == categoryName || tx.primaryCategoryId == categoryName else { return acc }
            return acc + max(0.0, tx.amount - tx.discountAmount - tx.refundAmount)
        }
    }

    public func dailyAvailableBudget(now: Date = Date()) -> Double {
        let period = currentBillingPeriod(now: now)
        let spentBefore = BillingPeriodEngine.spentBeforeToday(
            transactions: transactions,
            ledgerId: currentLedgerId,
            period: period,
            today: now
        )
        let remainingDays = BillingPeriodEngine.remainingDaysIncludingToday(in: period, today: now)
        return DynamicBudgetEngine.calculateDailyBudget(
            monthlyBudget: monthlyBudgetTotal,
            spentBeforeToday: spentBefore,
            remainingDaysIncludingToday: remainingDays
        )
    }

    public func todayExpenseTotal(now: Date = Date()) -> Double {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return 0 }
        return transactions.reduce(0.0) { sum, tx in
            guard tx.ledgerId == currentLedgerId,
                  tx.type == .expense,
                  tx.date >= start, tx.date < end else { return sum }
            return sum + max(0.0, tx.amount - tx.discountAmount - tx.refundAmount)
        }
    }

    /// Normalized 0…1 samples for home「30天趋势」sparkline, ending at current net worth.
    public func netWorthSparklineSamples(days: Int = 30, now: Date = Date()) -> [CGFloat] {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: now)
        var dailyDelta = Array(repeating: 0.0, count: max(days, 2))
        for tx in transactions {
            guard tx.includeInStats, tx.type != .transfer else { continue }
            let dayStart = cal.startOfDay(for: tx.date)
            guard let diff = cal.dateComponents([.day], from: dayStart, to: today).day,
                  diff >= 0, diff < dailyDelta.count else { continue }
            let idx = dailyDelta.count - 1 - diff
            let net = max(0.0, tx.amount - tx.discountAmount - tx.refundAmount)
            if tx.type == .income {
                dailyDelta[idx] += net
            } else if tx.type == .expense {
                dailyDelta[idx] -= net
            }
        }
        var series = Array(repeating: 0.0, count: dailyDelta.count)
        series[series.count - 1] = netWorth
        for i in stride(from: series.count - 2, through: 0, by: -1) {
            series[i] = series[i + 1] - dailyDelta[i + 1]
        }
        let minV = series.min() ?? 0
        let maxV = series.max() ?? 1
        let span = max(0.01, maxV - minV)
        return series.map { CGFloat(($0 - minV) / span) }
    }

    public var currentLedgerName: String {
        get { currentLedger.name }
        set {
            if let found = ledgers.first(where: { $0.name == newValue || $0.id == newValue }) {
                currentLedgerId = found.id
                saveState()
            }
        }
    }

    public var categoryBudgets: [CategoryBudgetItem] {
        currentLedger.categoryBudgets
    }

    /// Sorts category budgets in descending order of usage ratio (`spent / monthlyLimit`),
    /// so categories with higher percentage used always appear higher regardless of absolute RM amount.
    public static func sortCategoryBudgetsByUsageRatio(
        _ items: [CategoryBudgetItem],
        spentForCategory: (String) -> Double
    ) -> [CategoryBudgetItem] {
        items.sorted { lhs, rhs in
            let lhsSpent = max(0.0, spentForCategory(lhs.categoryName))
            let rhsSpent = max(0.0, spentForCategory(rhs.categoryName))
            let lhsRatio: Double = lhs.monthlyLimit > 0
                ? (lhsSpent / lhs.monthlyLimit)
                : (lhsSpent > 0 ? .infinity : 0.0)
            let rhsRatio: Double = rhs.monthlyLimit > 0
                ? (rhsSpent / rhs.monthlyLimit)
                : (rhsSpent > 0 ? .infinity : 0.0)
            if abs(lhsRatio - rhsRatio) > 1e-9 {
                return lhsRatio > rhsRatio
            }
            if abs(lhsSpent - rhsSpent) > 1e-9 {
                return lhsSpent > rhsSpent
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    public func sortedCategoryBudgets(in period: BillingPeriod? = nil) -> [CategoryBudgetItem] {
        let targetPeriod = period ?? currentBillingPeriod()
        return Self.sortCategoryBudgetsByUsageRatio(categoryBudgets) { categoryName in
            self.categorySpent(for: categoryName, in: targetPeriod)
        }
    }

    public func uncategorizedBudgetSpent(in period: BillingPeriod? = nil) -> Double {
        let targetPeriod = period ?? currentBillingPeriod()
        let budgetedNames = Set(categoryBudgets.map(\.categoryName))
        let budgetedIds = Set(categoryBudgets.map(\.categoryId))
        return transactions.reduce(0.0) { acc, tx in
            guard tx.ledgerId == currentLedgerId,
                  tx.includeInStats,
                  tx.type == .expense,
                  targetPeriod.contains(tx.date) else { return acc }
            let primaryName = tx.categoryPath.components(separatedBy: "-").first ?? tx.categoryPath
            if budgetedNames.contains(primaryName) || budgetedIds.contains(tx.primaryCategoryId) {
                return acc
            }
            return acc + max(0.0, tx.amount - tx.discountAmount - tx.refundAmount)
        }
    }

    public func categorySpent(for categoryName: String, year: Int, month: Int) -> Double {
        if monthStartDay != 1 {
            let cal = Calendar(identifier: .gregorian)
            let anchor = cal.date(from: DateComponents(year: year, month: month, day: monthStartDay)) ?? Date()
            return categorySpent(for: categoryName, in: BillingPeriodEngine.period(containing: anchor, startDay: monthStartDay))
        }
        let cal = Calendar(identifier: .gregorian)
        return transactions.reduce(0.0) { acc, tx in
            guard tx.ledgerId == currentLedgerId,
                  tx.includeInStats,
                  tx.type == .expense else { return acc }
            let comps = cal.dateComponents([.year, .month], from: tx.date)
            guard comps.year == year && comps.month == month else { return acc }
            let primaryName = tx.categoryPath.components(separatedBy: "-").first ?? tx.categoryPath
            guard primaryName == categoryName || tx.primaryCategoryId == categoryName else { return acc }
            let net = max(0.0, tx.amount - tx.discountAmount - tx.refundAmount)
            return acc + net
        }
    }

    public func setCustomDailyBudget(dateKey: String, amount: Double) {
        var ledger = currentLedger
        ledger.customDailyBudgets[dateKey] = max(0.0, amount)
        currentLedger = ledger
        saveState()
    }

    public func updateMonthlyBudget(_ newBudget: Double) {
        var ledger = currentLedger
        ledger.monthlyBudget = max(0.0, newBudget)
        currentLedger = ledger
        saveState()
    }

    public func setCategoryBudget(categoryName: String, monthlyLimit: Double, iconName: String = "🏷️") {
        var ledger = currentLedger
        if let idx = ledger.categoryBudgets.firstIndex(where: { $0.categoryName == categoryName }) {
            ledger.categoryBudgets[idx].monthlyLimit = max(0.0, monthlyLimit)
        } else {
            let newId = "cb_\(UUID().uuidString.prefix(6))"
            let newItem = CategoryBudgetItem(
                id: newId,
                categoryId: "exp_\(categoryName)",
                categoryName: categoryName,
                iconName: iconName,
                monthlyLimit: max(0.0, monthlyLimit),
                sortOrder: ledger.categoryBudgets.count
            )
            ledger.categoryBudgets.append(newItem)
        }
        currentLedger = ledger
        saveState()
    }

    public func removeCategoryBudget(categoryName: String) {
        var ledger = currentLedger
        ledger.categoryBudgets.removeAll(where: { $0.categoryName == categoryName })
        currentLedger = ledger
        saveState()
    }

    public var netWorth: Double { netWorthTotal() }

    public var totalAssets: Double {
        accounts
            .filter { !$0.isLiability && $0.includeInAssets }
            .reduce(0.0) { $0 + $1.balance }
    }

    /// Accounts ordered for the assets list: special-focus first, then original order.
    public var accountsForDisplay: [AccountItem] {
        let focused = accounts.filter(\.isSpecialFocus)
        let rest = accounts.filter { !$0.isSpecialFocus }
        return focused + rest
    }

    public var defaultBookkeepingAccount: AccountItem? {
        accounts.first(where: \.isDefaultAccount) ?? accounts.first
    }

    public var totalLiabilities: Double {
        accounts.filter { $0.isLiability }.reduce(0.0) { $0 + $1.balance }
    }

    /// Pending reimbursement = sum of expense txs tagged 待报销/报销 (net of discount/refund).
    public var pendingReimbursementTransactions: [TransactionItem] {
        transactions.filter { tx in
            guard tx.type == .expense else { return false }
            return tx.tags.contains(where: { tag in
                let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                return t == "待报销" || t == "报销"
            })
        }
    }

    public var pendingReimbursementAmount: Double {
        let fromTags = pendingReimbursementTransactions.reduce(0.0) { sum, tx in
            sum + max(0.0, tx.amount - tx.discountAmount - tx.refundAmount)
        }
        // Keep legacy manual reimbursableAmount as additive only when no tagged bills exist
        // (demo seed); otherwise tags are the source of truth.
        if fromTags > 0.009 { return ((fromTags * 100).rounded()) / 100 }
        return reimbursableAmount
    }

    public var recordedDaysCount: Int {
        let cal = Calendar(identifier: .gregorian)
        let uniqueDays = Set(transactions.map { cal.startOfDay(for: $0.date) })
        return uniqueDays.count
    }

    public var totalRecordsCount: Int {
        transactions.count
    }

    public var streakDaysCount: Int {
        transactions.isEmpty ? 0 : 1
    }

    /// Imports Mimi Money dual-table CSV text and reconciles account balances & audit logs
    @discardableResult
    public func importMimiCSV(_ csvText: String, replaceExisting: Bool = false) -> Int {
        applyImportedTransactions(MimiCSVService.parseMimiCSV(csvText), replaceExisting: replaceExisting)
    }

    /// Imports 咔皮同款 Excel（收支账单 + 内部转账）
    @discardableResult
    public func importKapiXLSX(_ data: Data, replaceExisting: Bool = false) throws -> Int {
        applyImportedTransactions(try MimiKapiXLSXService.parseXLSX(data: data), replaceExisting: replaceExisting)
    }

    @discardableResult
    private func applyImportedTransactions(_ parsed: [TransactionItem], replaceExisting: Bool) -> Int {
        guard !parsed.isEmpty else { return 0 }
        if replaceExisting {
            transactions = []
            auditLogs = []
            for idx in accounts.indices {
                accounts[idx].balance = 0.0
            }
        }
        for item in parsed.sorted(by: { $0.date < $1.date }) {
            addTransaction(item, at: item.date)
        }
        sanitizeImportedSharedStringArtifacts()
        saveState()
        return parsed.count
    }

    private func filteredTransactions(startDate: Date?, endDate: Date?) -> [TransactionItem] {
        if let start = startDate, let end = endDate {
            return transactions.filter { $0.date >= start && $0.date <= end }
        } else if let start = startDate {
            return transactions.filter { $0.date >= start }
        } else if let end = endDate {
            return transactions.filter { $0.date <= end }
        }
        return transactions
    }

    public func exportMimiCSV(startDate: Date? = nil, endDate: Date? = nil) -> String {
        MimiCSVService.exportMimiCSV(transactions: filteredTransactions(startDate: startDate, endDate: endDate))
    }

    public func exportMimiCSV() -> String {
        exportMimiCSV(startDate: nil, endDate: nil)
    }

    public func exportKapiXLSX(startDate: Date? = nil, endDate: Date? = nil) throws -> Data {
        try MimiKapiXLSXService.exportXLSX(transactions: filteredTransactions(startDate: startDate, endDate: endDate))
    }

    public func groupedTransactionsByDay() -> [(date: Date, items: [TransactionItem])] {
        if let cached = cachedGroupedTransactions {
            return cached
        }
        let cal = Calendar(identifier: .gregorian)
        let filtered = transactions.filter { $0.ledgerId == currentLedgerId }
        var buckets: [Date: [TransactionItem]] = [:]
        for tx in filtered {
            let dayStart = cal.startOfDay(for: tx.date)
            buckets[dayStart, default: []].append(tx)
        }
        let result = buckets
            .map { (date: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
        cachedGroupedTransactions = result
        return result
    }

    public func auditLogs(for accountName: String) -> [AccountAuditLog] {
        let targetId = accounts.first(where: { $0.name == accountName || $0.id == accountName })?.id ?? accountName
        return auditLogs.filter { $0.accountId == targetId || $0.accountId == accountName }
    }

    public func monthlyExpenseTotal(year: Int, month: Int) -> Double {
        // When custom monthStartDay is set, prefer the billing period that starts in this calendar month.
        if monthStartDay != 1 {
            let cal = Calendar(identifier: .gregorian)
            let anchor = cal.date(from: DateComponents(year: year, month: month, day: monthStartDay)) ?? Date()
            return expenseTotal(in: BillingPeriodEngine.period(containing: anchor, startDay: monthStartDay))
        }
        let cal = Calendar(identifier: .gregorian)
        return transactions.reduce(0.0) { acc, tx in
            guard tx.ledgerId == currentLedgerId,
                  tx.includeInStats,
                  tx.type == .expense else { return acc }
            let comps = cal.dateComponents([.year, .month], from: tx.date)
            guard comps.year == year && comps.month == month else { return acc }
            let net = max(0.0, tx.amount - tx.discountAmount - tx.refundAmount)
            return acc + net
        }
    }

    public func monthlyIncomeTotal(year: Int, month: Int) -> Double {
        if monthStartDay != 1 {
            let cal = Calendar(identifier: .gregorian)
            let anchor = cal.date(from: DateComponents(year: year, month: month, day: monthStartDay)) ?? Date()
            return incomeTotal(in: BillingPeriodEngine.period(containing: anchor, startDay: monthStartDay))
        }
        let cal = Calendar(identifier: .gregorian)
        return transactions.reduce(0.0) { acc, tx in
            guard tx.ledgerId == currentLedgerId,
                  tx.includeInStats,
                  tx.type == .income else { return acc }
            let comps = cal.dateComponents([.year, .month], from: tx.date)
            guard comps.year == year && comps.month == month else { return acc }
            return acc + tx.amount
        }
    }

    public func netWorthTotal() -> Double {
        accounts.reduce(0.0) { sum, acc in
            guard acc.includeInAssets else { return sum }
            return sum + (acc.isLiability ? -acc.balance : acc.balance)
        }
    }

    public func categoryTitle(for tx: TransactionItem) -> String {
        if tx.type == .transfer { return "转账" }
        let groups = tx.type == .expense ? expenseCategories : incomeCategories
        guard let group = groups.first(where: { $0.id == tx.primaryCategoryId }) else {
            return tx.primaryCategoryId
        }
        if let subId = tx.subCategoryId,
           let sub = group.subCategories.first(where: { $0.id == subId }) {
            return "\(group.name)-\(sub.name)"
        }
        return group.name
    }

    public func categoryIcon(for tx: TransactionItem) -> String {
        if tx.type == .transfer { return "⇄" }
        let groups = tx.type == .expense ? expenseCategories : incomeCategories
        guard let group = groups.first(where: { $0.id == tx.primaryCategoryId }) else {
            return "💰"
        }
        if let subId = tx.subCategoryId,
           let sub = group.subCategories.first(where: { $0.id == subId }) {
            return sub.displayBadgeToken
        }
        return group.displayBadgeToken
    }

    public func accountName(for accountId: String?) -> String {
        guard let accountId,
              let acc = accounts.first(where: { $0.id == accountId }) else {
            return "无账户"
        }
        return acc.name
    }

    public func resetToDemoData() {
        let demo = Self.makeDemoAppState()
        self.ledgers = demo.ledgers
        self.currentLedgerId = demo.currentLedgerId
        self.accounts = demo.accounts
        self.transactions = demo.transactions
        self.auditLogs = demo.auditLogs
        self.expenseCategories = demo.expenseCategories
        self.incomeCategories = demo.incomeCategories
        self.tags = demo.tags
        saveState()
    }

    public func clearAllDemoTransactions() {
        resetToCleanEmpty()
    }

    public func resetToCleanEmpty() {
        let clean = Self.makeCleanEmptyAppState()
        self.ledgers = clean.ledgers
        self.currentLedgerId = clean.currentLedgerId
        self.accounts = clean.accounts
        self.transactions = []
        self.auditLogs = []
        self.reimbursableAmount = 0.0
        self.expenseCategories = clean.expenseCategories
        self.incomeCategories = clean.incomeCategories
        self.tags = clean.tags
        self.monthStartDay = clean.monthStartDay
        self.hasCompletedOnboarding = clean.hasCompletedOnboarding
        saveState()
    }

    public static func makeCleanEmptyAppState() -> PersistedAppState {
        let zeroAccounts = DefaultCatalog.defaultAccounts().map { acc in
            AccountItem(
                id: acc.id,
                name: acc.name,
                subtitle: acc.subtitle,
                badgeText: acc.badgeText,
                iconName: acc.iconName,
                balance: 0.00,
                isLiability: acc.isLiability
            )
        }
        return PersistedAppState(
            ledgers: [DefaultCatalog.defaultLedger()],
            currentLedgerId: "ledger_main",
            accounts: zeroAccounts,
            transactions: [],
            auditLogs: [],
            expenseCategories: DefaultCatalog.standardExpenseCategories(),
            incomeCategories: DefaultCatalog.standardIncomeCategories(),
            tags: ["报销", "旅行", "固定支出", "家庭"],
            monthStartDay: 1,
            hasCompletedOnboarding: false
        )
    }

    private func applyBalanceEffect(for tx: TransactionItem, multiplier: Double) {
        let netAmount = max(0.0, tx.amount - tx.discountAmount - tx.refundAmount)
        let resolvedSrcId = tx.accountId ?? DefaultCatalog.resolveAccountId(from: tx.accountName)
        let resolvedDstId = tx.targetAccountId ?? (tx.targetAccountName.map { DefaultCatalog.resolveAccountId(from: $0) } ?? nil)

        switch tx.type {
        case .expense:
            if let accId = resolvedSrcId, let idx = accounts.firstIndex(where: { $0.id == accId || $0.name == tx.accountName }) {
                accounts[idx].balance = ((accounts[idx].balance - netAmount * multiplier) * 100.0).rounded() / 100.0
            }
        case .income:
            if let accId = resolvedSrcId, let idx = accounts.firstIndex(where: { $0.id == accId || $0.name == tx.accountName }) {
                accounts[idx].balance = ((accounts[idx].balance + netAmount * multiplier) * 100.0).rounded() / 100.0
            }
        case .transfer:
            if let fromId = resolvedSrcId, let fromIdx = accounts.firstIndex(where: { $0.id == fromId || $0.name == tx.accountName }) {
                accounts[fromIdx].balance = ((accounts[fromIdx].balance - netAmount * multiplier) * 100.0).rounded() / 100.0
            }
            if let toId = resolvedDstId, let toIdx = accounts.firstIndex(where: { $0.id == toId || $0.name == tx.targetAccountName }) {
                accounts[toIdx].balance = ((accounts[toIdx].balance + netAmount * multiplier) * 100.0).rounded() / 100.0
            }
        }
    }

    private func appendAuditLog(for tx: TransactionItem, action: AuditActionType, loggedAt: Date) {
        let net = max(0.0, tx.amount - tx.discountAmount - tx.refundAmount)
        let title = categoryTitle(for: tx).components(separatedBy: "-").last ?? categoryTitle(for: tx)
        let note = tx.note.isEmpty ? (action == .updated ? "账单编辑" : title) : tx.note
        let typeLabel = tx.type == .transfer ? "转账" : tx.type.rawValue

        if let accId = tx.accountId, let acc = accounts.first(where: { $0.id == accId }) {
            let srcNote: String
            if tx.type == .transfer {
                let dest = accountName(for: tx.targetAccountId)
                srcNote = note.isEmpty ? "转出 → \(dest)" : note
            } else {
                srcNote = note
            }
            auditLogs.insert(
                AccountAuditLog(
                    accountId: accId,
                    action: action,
                    transactionType: tx.type,
                    categoryTitle: "\(typeLabel) | \(title)",
                    note: srcNote,
                    amount: net,
                    balanceAfter: acc.balance,
                    billDate: tx.date,
                    loggedAt: loggedAt,
                    transactionId: tx.id,
                    isInflow: tx.type == .income
                ),
                at: 0
            )
        }

        // 转账入款账户也写明细，否则对方账户余额变了但记录空白
        if tx.type == .transfer,
           let dstId = tx.targetAccountId ?? tx.targetAccountName.flatMap({ DefaultCatalog.resolveAccountId(from: $0) }),
           let dst = accounts.first(where: { $0.id == dstId }) {
            let srcName = accountName(for: tx.accountId)
            auditLogs.insert(
                AccountAuditLog(
                    accountId: dstId,
                    action: action,
                    transactionType: .transfer,
                    categoryTitle: "转账 | \(title)",
                    note: note.isEmpty ? "转入 ← \(srcName)" : note,
                    amount: net,
                    balanceAfter: dst.balance,
                    billDate: tx.date,
                    loggedAt: loggedAt,
                    transactionId: tx.id,
                    isInflow: true
                ),
                at: 0
            )
        }
    }

    public func transaction(forAuditLog log: AccountAuditLog) -> TransactionItem? {
        if log.action == .deleted { return nil }
        if let tid = log.transactionId,
           let exact = transactions.first(where: { $0.id == tid }) {
            return exact
        }
        let accountNames: Set<String> = {
            var names: Set<String> = [log.accountId]
            if let acc = accounts.first(where: { $0.id == log.accountId || $0.name == log.accountId }) {
                names.insert(acc.id)
                names.insert(acc.name)
            }
            return names
        }()
        // Fallback for older logs without transactionId
        return transactions.first { tx in
            abs(tx.amount - log.amount) < 0.009
                && tx.type == log.transactionType
                && (accountNames.contains(tx.accountId ?? "") || accountNames.contains(tx.accountName))
                && abs(tx.date.timeIntervalSince(log.billDate)) < 86_400 * 2
        }
    }

    /// Reloads persisted state from disk. Used when the Shortcuts intent (running in a
    /// background process) has written new bills before the app UI is brought to front.
    public func reloadFromDisk() {
        guard !inMemory,
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode(PersistedAppState.self, from: data) else { return }
        ledgers = decoded.ledgers
        currentLedgerId = decoded.currentLedgerId
        accounts = decoded.accounts
        transactions = decoded.transactions
        auditLogs = decoded.auditLogs
        expenseCategories = decoded.expenseCategories
        incomeCategories = decoded.incomeCategories
        tags = decoded.tags
        monthStartDay = decoded.monthStartDay
        hasCompletedOnboarding = decoded.hasCompletedOnboarding
        if let pendingData = try? Data(contentsOf: pendingScansURL),
           let pendingDecoded = try? JSONDecoder().decode([TransactionItem].self, from: pendingData) {
            pendingScanTransactions = pendingDecoded
        }
        sanitizeImportedSharedStringArtifacts()
        DefaultCatalog.syncLiveAccounts(accounts)
        recalculateAllAccountBalances()
    }

    public func saveState() {
        DefaultCatalog.syncLiveAccounts(accounts)
        guard !inMemory else { return }
        let state = PersistedAppState(
            ledgers: ledgers,
            currentLedgerId: currentLedgerId,
            accounts: accounts,
            transactions: transactions,
            auditLogs: auditLogs,
            expenseCategories: expenseCategories,
            incomeCategories: incomeCategories,
            tags: tags,
            monthStartDay: monthStartDay,
            hasCompletedOnboarding: hasCompletedOnboarding
        )
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    /// Anonymous demo seed for UI/dev preview — no personal backup data.
    public static func makeDemoAppState() -> PersistedAppState {
        let cal = Calendar(identifier: .gregorian)
        func makeDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)) ?? Date()
        }

        let txs: [TransactionItem] = [
            TransactionItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                ledgerId: "ledger_main",
                type: .expense,
                amount: 38.78,
                currency: .myr,
                primaryCategoryId: "exp_transport",
                subCategoryId: "exp_trans_fuel",
                accountId: "acc_pbb",
                note: "示例加油",
                date: makeDate(2026, 11, 8, 21, 59)
            ),
            TransactionItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                ledgerId: "ledger_main",
                type: .expense,
                amount: 5.90,
                currency: .myr,
                primaryCategoryId: "exp_food",
                subCategoryId: "exp_food_snack",
                accountId: "acc_tng",
                note: "示例零食",
                counterparty: "示例商户",
                date: makeDate(2026, 11, 8, 16, 56)
            ),
            TransactionItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                ledgerId: "ledger_main",
                type: .expense,
                amount: 28.00,
                currency: .myr,
                primaryCategoryId: "exp_entertainment",
                subCategoryId: "exp_ent_offline",
                accountId: "acc_tng",
                note: "示例娱乐",
                date: makeDate(2026, 11, 7, 23, 4)
            ),
            TransactionItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                ledgerId: "ledger_main",
                type: .expense,
                amount: 8.30,
                currency: .myr,
                primaryCategoryId: "exp_food",
                subCategoryId: "exp_food_restaurant",
                accountId: "acc_tng",
                note: "示例午餐",
                date: makeDate(2026, 11, 6, 13, 15)
            ),
            TransactionItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
                ledgerId: "ledger_main",
                type: .income,
                amount: 1000.00,
                currency: .myr,
                primaryCategoryId: "inc_salary",
                subCategoryId: nil,
                accountId: "acc_pbb",
                note: "示例工资",
                date: makeDate(2026, 11, 6, 10, 0)
            ),
            TransactionItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
                ledgerId: "ledger_main",
                type: .income,
                amount: 20.00,
                currency: .myr,
                primaryCategoryId: "inc_custom_transfer",
                subCategoryId: nil,
                accountId: "acc_tng",
                note: "示例收款",
                date: makeDate(2026, 11, 5, 19, 0)
            ),
            TransactionItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
                ledgerId: "ledger_main",
                type: .expense,
                amount: 12.00,
                currency: .myr,
                primaryCategoryId: "exp_shopping",
                subCategoryId: "exp_shop_daily",
                accountId: "acc_pbb",
                note: "示例购物",
                date: makeDate(2026, 11, 1, 20, 15)
            )
        ]

        let logs: [AccountAuditLog] = [
            AccountAuditLog(
                accountId: "acc_tng",
                action: .created,
                transactionType: .expense,
                categoryTitle: "支出 | 零食甜品",
                note: "示例零食",
                amount: 5.90,
                balanceAfter: 94.10,
                billDate: makeDate(2026, 11, 8, 16, 56),
                loggedAt: makeDate(2026, 11, 8, 16, 57)
            ),
            AccountAuditLog(
                accountId: "acc_tng",
                action: .updated,
                transactionType: .income,
                categoryTitle: "收入 | 别人转账",
                note: "账单编辑",
                amount: 20.00,
                balanceAfter: 100.00,
                billDate: makeDate(2026, 11, 5, 19, 0),
                loggedAt: makeDate(2026, 11, 5, 19, 5)
            )
        ]

        return PersistedAppState(
            ledgers: [DefaultCatalog.defaultLedger()],
            currentLedgerId: "ledger_main",
            accounts: DefaultCatalog.defaultAccounts(),
            transactions: txs,
            auditLogs: logs,
            expenseCategories: DefaultCatalog.standardExpenseCategories(),
            incomeCategories: DefaultCatalog.standardIncomeCategories(),
            tags: ["报销", "旅行", "固定支出", "家庭"],
            monthStartDay: 1,
            hasCompletedOnboarding: true
        )
    }
}

private extension Array {
    subscript(idx index: Int) -> Element {
        get { self[index] }
        set { self[index] = newValue }
    }
}
