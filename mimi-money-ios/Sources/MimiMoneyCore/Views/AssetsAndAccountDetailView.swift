import SwiftUI

public struct AssetsAndAccountDetailView: View {
    @ObservedObject public var store: MimiStore
    @ObservedObject public var aiEngine: MimiAIEngine
    public var onDismiss: () -> Void

    /// Single source of truth for 资产 overlay ↔ 账户详情 ↔ 记账/转账 sheets.
    @State private var nav = AssetsAccountNavigationState(isAssetsPresented: true)
    @State private var showBalanceEditSheet: Bool = false
    @State private var newBalanceInput: String = ""
    @State private var balanceEditMode: Int = 0 // 0: 设定期初起始资金, 1: 校准当前余额
    @State private var detailTabMode: String = "明细" // "明细" (audit logs) vs "账单" (bills)
    @State private var showAddAccountSheet: Bool = false
    @State private var newAccountName: String = ""
    @State private var newAccountBalance: String = ""
    @State private var billForDetail: TransactionItem? = nil
    /// Keys: `"yyyy-M"` — months whose detail/bill lists are collapsed.
    @State private var collapsedMonthKeys: Set<String> = []
    /// Identifiable route for 「…」→ 编辑账户. Bool + `if let` sheets present blank white content.
    @State private var editAccountRoute: EditAccountSheetRoute? = nil
    @State private var showPendingReimbursementSheet: Bool = false

    public init(store: MimiStore, aiEngine: MimiAIEngine, onDismiss: @escaping () -> Void) {
        self.store = store
        self.aiEngine = aiEngine
        self.onDismiss = onDismiss
    }

    /// Apply nav actions and only dismiss the root 资产 overlay when the reducer says so.
    private func dispatch(_ action: AssetsAccountNavigationState.Action) {
        var next = nav
        let effect = next.apply(action)
        nav = next
        if effect.dismissAssetsOverlay {
            onDismiss()
        }
    }

    private var selectedAccountBinding: Binding<String?> {
        Binding(
            get: { nav.selectedAccountID },
            set: { newValue in
                if let id = newValue {
                    dispatch(.openAccount(id))
                } else {
                    // Interactive pop / destination clear: pop detail only — never 记账/home.
                    var next = nav
                    next.selectedAccountID = nil
                    next.entryRoute = nil
                    nav = next
                }
            }
        )
    }

    private var entryRouteBinding: Binding<AssetsAccountNavigationState.AccountEntryRoute?> {
        Binding(
            get: { nav.entryRoute },
            set: { newValue in
                if let route = newValue {
                    dispatch(.openEntry(route))
                } else {
                    dispatch(.dismissEntry)
                }
            }
        )
    }

    /// iOS: topBarLeading avoids cancellationAction conflating detail pop with overlay dismiss.
    /// macOS host tests: cancellationAction (topBarLeading is unavailable).
    private var backToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .cancellationAction
        #endif
    }

    private func monthKey(from date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)"
    }

    private func monthTitle(year: Int, month: Int) -> String {
        "\(year)年\(month)月"
    }

    private func isMonthExpanded(_ key: String) -> Bool {
        !collapsedMonthKeys.contains(key)
    }

    private func toggleMonthExpanded(_ key: String) {
        if collapsedMonthKeys.contains(key) {
            collapsedMonthKeys.remove(key)
        } else {
            collapsedMonthKeys.insert(key)
        }
    }

    private func billSecondaryLine(for tx: TransactionItem) -> String {
        let time = formattedBillTime(tx.date)
        let detail: String = {
            let note = tx.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { return note }
            let party = tx.counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
            if !party.isEmpty { return party }
            return ""
        }()
        return detail.isEmpty ? time : "\(time) | \(detail)"
    }

    private func billCategoryTitle(for tx: TransactionItem) -> String {
        if tx.type == .transfer { return "转账" }
        let parts = tx.categoryPath
            .components(separatedBy: "-")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.last ?? tx.categoryPath
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    netWorthTopBanner
                    reimbursementAndLendingRow
                    accountGroupCard
                }
                .padding(16)
            }
            .background(MimiTheme.background.ignoresSafeArea())
            .navigationTitle(MimiL10n.string("资产"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // Prefer topBarLeading on iOS so detail back ≠ overlay dismiss → 记账.
                ToolbarItem(placement: backToolbarPlacement) {
                    Button {
                        dispatch(.back)
                    } label: {
                        Image(systemName: "chevron.left")
                            .mimiFont(15, weight: .semibold)
                            .foregroundColor(MimiTheme.textPrimary)
                            .frame(width: MimiHIG.minTouch, height: MimiHIG.minTouch)
                            .contentShape(Rectangle())
                    }
                    .mimiPressable()
                    .accessibilityLabel(MimiL10n.string("返回"))
                    .accessibilityHint(MimiL10n.string("返回记账首页"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showAddAccountSheet = true
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "plus")
                                .mimiFont(12, weight: .bold)
                            Text("添加账户", bundle: .mimiModule)
                                .mimiFont(13, weight: .semibold)
                        }
                        .foregroundColor(MimiTheme.expenseBlue)
                    }
                }
            }
            .navigationDestination(item: selectedAccountBinding) { accountID in
                if let account = store.accounts.first(where: { $0.id == accountID }) {
                    accountDetailSheet(for: account)
                } else {
                    Text("账户不存在", bundle: .mimiModule)
                        .foregroundColor(MimiTheme.textMuted)
                }
            }
            // 账单详情挂在资产 NavigationStack 上，避免账户详情再嵌套 sheet
            .sheet(item: $billForDetail) { tx in
                BillDetailSheetView(store: store, transaction: tx) {
                    billForDetail = nil
                }
                .mimiInteractiveSheet()
            }
            // sheet(item:) + unique presentationID so 转账 always mounts on transfer tab
            // (stale @State selectedTab / UIPageViewController caused 支出 after dismiss).
            // .id on content + presentationID into the sheet forces a full rebuild each open.
            .sheet(item: entryRouteBinding) { route in
                RecordAndAISheetView(
                    store: store,
                    aiEngine: aiEngine,
                    initialAIMode: false,
                    initialTab: AccountEntrySheetBootstrap.intendedTab(for: route),
                    presentationID: route.presentationID,
                    initialAccountName: route.accountName,
                    onDismiss: { dispatch(.dismissEntry) },
                    onOpenCategorySettings: {
                        dispatch(.dismissEntry)
                        // Category manager is opened from root drawer; from assets entry just dismiss.
                    },
                    onEditRecognizedTransaction: { tx in
                        dispatch(.dismissEntry)
                        billForDetail = tx
                    }
                )
                .id(route.presentationID)
                // Full-screen 记账/转账; axis lock lives inside RecordAndAISheetView (v1.3.13).
                .mimiInteractiveSheet(detents: [.large])
            }
            .sheet(item: $editAccountRoute) { route in
                EditAccountView(
                    store: store,
                    accountId: route.id,
                    onDismiss: { editAccountRoute = nil },
                    onDeleted: {
                        // Pop detail only — deleting an account must never dismiss 资产 → 记账.
                        if nav.selectedAccountID == route.id {
                            var next = nav
                            next.selectedAccountID = nil
                            next.entryRoute = nil
                            nav = next
                        }
                        editAccountRoute = nil
                    }
                )
                .mimiInteractiveSheet()
            }
            .sheet(isPresented: $showPendingReimbursementSheet) {
                pendingReimbursementSheet
                    .mimiInteractiveSheet()
            }
            .sheet(isPresented: $showAddAccountSheet) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("新增资产账户", bundle: .mimiModule)
                            .mimiFont(18, weight: .bold)
                            .foregroundColor(MimiTheme.textPrimary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("账户名称", bundle: .mimiModule)
                                .mimiFont(13, weight: .medium)
                                .foregroundColor(MimiTheme.textSecondary)
                            TextField("例如: Maybank / GrabPay / 备用金", text: $newAccountName)
                                .mimiFont(14)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(MimiTheme.background))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("起始开局余额 (RM)", bundle: .mimiModule)
                                .mimiFont(13, weight: .medium)
                                .foregroundColor(MimiTheme.textSecondary)
                            TextField("0.00", text: $newAccountBalance)
                                .mimiFont(14)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(MimiTheme.background))
                        }

                        Button {
                            let trimmed = newAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            // Empty opening-balance field persists 0 (not leftover / nil fallback to balance).
                            let opening = AccountBalanceEditPrefill.parseNewAccountOpeningBalance(newAccountBalance)
                            let item = AccountItem(
                                id: "acc_\(UUID().uuidString.prefix(6))",
                                name: trimmed,
                                subtitle: "自定义账户",
                                iconName: "💳",
                                balance: opening,
                                initialBalance: opening,
                                createdAt: Date()
                            )
                            store.addAccount(item)
                            showAddAccountSheet = false
                            newAccountName = ""
                            newAccountBalance = ""
                        } label: {
                            Text("保存并创建账户", bundle: .mimiModule)
                                .mimiFont(15, weight: .bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(MimiTheme.expenseBlue))
                        }
                        .mimiPressable()

                        Spacer()
                    }
                    .padding(20)
                    .navigationTitle(MimiL10n.string("添加账户"))
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(MimiL10n.string("取消")) { showAddAccountSheet = false }
                        }
                    }
                }
                .mimiInteractiveSheet()
            }
        }
        // Overlay-level edge swipe only when not drilled into 账户详情 / 记账 sheet.
        .mimiEdgeSwipeBack(
            isEnabled: nav.selectedAccountID == nil && nav.entryRoute == nil
        ) {
            dispatch(.back)
        }
    }

    // MARK: - Net Worth Overview Banner (IMG_2258)

    private var netWorthTopBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("净资产", bundle: .mimiModule)
                .mimiFont(13, weight: .medium)
                .foregroundColor(MimiTheme.textSecondary)

            Text(MimiTheme.formatRM(store.netWorth))
                .mimiFont(28, weight: .bold, design: .rounded)
                .foregroundColor(store.netWorth < -0.0001 ? MimiTheme.dangerEmphasis : MimiTheme.textPrimary)

            HStack(spacing: 24) {
                Text("资产 \(MimiTheme.formatRM(store.totalAssets))")
                    .mimiFont(12)
                    .foregroundColor(store.totalAssets < -0.0001 ? MimiTheme.dangerEmphasis : MimiTheme.textSecondary)
                Text("负债 \(MimiTheme.formatRM(store.totalLiabilities))")
                    .mimiFont(12)
                    .foregroundColor(MimiTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(MimiTheme.assetCream)
        )
    }

    // MARK: - Reimbursement row (gold: single grey bar 待报销)

    private var reimbursementAndLendingRow: some View {
        Button {
            showPendingReimbursementSheet = true
        } label: {
            HStack {
                Text("待报销", bundle: .mimiModule)
                    .mimiFont(13, weight: .medium)
                    .foregroundColor(MimiTheme.textSecondary)
                Spacer()
                Text(MimiTheme.formatRM(store.pendingReimbursementAmount))
                    .mimiFont(15, weight: .bold, design: .rounded)
                    .foregroundColor(MimiTheme.textPrimary)
                Image(systemName: "chevron.right")
                    .mimiFont(11, weight: .semibold)
                    .foregroundColor(MimiTheme.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: MimiHIG.minTouch)
            .background(RoundedRectangle(cornerRadius: 14).fill(MimiTheme.surfaceMuted))
            .contentShape(Rectangle())
        }
        .mimiPressable()
        .accessibilityLabel("待报销 \(MimiTheme.formatRM(store.pendingReimbursementAmount))")
        .accessibilityHint(MimiL10n.string("查看并处理待报销账单"))
    }

    private var pendingReimbursementSheet: some View {
        NavigationStack {
            Group {
                let items = store.pendingReimbursementTransactions
                if items.isEmpty && store.pendingReimbursementAmount < 0.009 {
                    Text("暂无待报销账单。记账时打开「待报销」或打上「报销」标签即可汇总到这里。", bundle: .mimiModule)
                        .mimiFont(14)
                        .foregroundColor(MimiTheme.textSecondary)
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    List {
                        Section {
                            HStack {
                                Text("待报销合计", bundle: .mimiModule)
                                Spacer()
                                Text(MimiTheme.formatRM(store.pendingReimbursementAmount))
                                    .foregroundColor(MimiTheme.incomeOrange)
                                    .mimiFont(16, weight: .bold, design: .rounded)
                            }
                        }
                        ForEach(items) { tx in
                            Button {
                                showPendingReimbursementSheet = false
                                billForDetail = tx
                            } label: {
                                HStack(spacing: 12) {
                                    MimiStickerIconView(
                                        iconName: tx.iconName,
                                        categoryName: tx.categoryPath,
                                        transactionType: tx.type,
                                        size: 34
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tx.categoryPath)
                                            .mimiFont(14, weight: .semibold)
                                            .foregroundColor(MimiTheme.textPrimary)
                                        Text(tx.note.isEmpty ? store.accountName(for: tx.accountId) : tx.note)
                                            .mimiFont(12)
                                            .foregroundColor(MimiTheme.textMuted)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(MimiTheme.formatRM(tx.amount))
                                        .mimiFont(15, weight: .bold, design: .rounded)
                                        .foregroundColor(MimiTheme.expenseBlue)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(MimiL10n.string("已报销")) {
                                    store.clearPendingReimbursementTag(on: tx.id)
                                }
                                .tint(MimiTheme.balanceGreen)
                            }
                        }
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #else
                    .listStyle(.inset)
                    #endif
                }
            }
            .background(MimiTheme.background.ignoresSafeArea())
            .navigationTitle(MimiL10n.string("待报销"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(MimiL10n.string("关闭")) { showPendingReimbursementSheet = false }
                }
            }
        }
    }

    // MARK: - Account List Card (现金, CIMB, TNGewallet, PBBank)

    private var accountGroupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("资金账户 (资产)", bundle: .mimiModule)
                    .mimiFont(14, weight: .bold)
                    .foregroundColor(MimiTheme.textPrimary)
                Spacer()
                Button {
                    showAddAccountSheet = true
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "plus")
                            .mimiFont(11, weight: .bold)
                        Text("添加账户", bundle: .mimiModule)
                            .mimiFont(12, weight: .semibold)
                    }
                    .foregroundColor(MimiTheme.expenseBlue)
                }
                .mimiPressable()
            }

            ForEach(store.accountsForDisplay) { account in
                Button {
                    balanceEditMode = AccountBalanceEditPrefill.Mode.setOpening.rawValue
                    newBalanceInput = AccountBalanceEditPrefill.formattedInput(
                        mode: .setOpening,
                        balance: account.balance,
                        initialBalance: account.initialBalance
                    )
                    detailTabMode = "账单"
                    showBalanceEditSheet = false
                    dispatch(.openAccount(account.id))
                } label: {
                    HStack(spacing: 12) {
                        MimiStickerIconView(
                            iconName: account.iconName,
                            categoryName: account.name,
                            transactionType: .income,
                            size: 40
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(account.name)
                                    .mimiFont(15, weight: .semibold)
                                    .foregroundColor(MimiTheme.textPrimary)
                                if account.isSpecialFocus {
                                    Image(systemName: "star.fill")
                                        .mimiFont(10)
                                        .foregroundColor(MimiTheme.incomeOrange)
                                        .accessibilityLabel(MimiL10n.string("特别关注"))
                                }
                                if account.isDefaultAccount {
                                    Text("默认", bundle: .mimiModule)
                                        .mimiFont(10, weight: .semibold)
                                        .foregroundColor(MimiTheme.expenseBlue)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(MimiTheme.tintBlueChip))
                                }
                            }
                            Text(account.subtitle.isEmpty ? "自定义余额" : account.subtitle)
                                .mimiFont(11)
                                .foregroundColor(MimiTheme.textMuted)
                        }

                        Spacer()

                        Text(MimiTheme.formatRM(account.balance))
                            .mimiFont(16, weight: .bold, design: .rounded)
                            .foregroundColor(account.balance < -0.0001 ? MimiTheme.dangerEmphasis : MimiTheme.textPrimary)

                        Image(systemName: "chevron.right")
                            .mimiFont(11)
                            .foregroundColor(MimiTheme.textMuted)
                    }
                    .padding(.vertical, 8)
                }
                .mimiPressable()

                if account.id != store.accountsForDisplay.last?.id {
                    Divider()
                }
            }

        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(MimiTheme.cardBackground))
    }

    // MARK: - Account Detail (push，避免 sheet 套 sheet 点了卡住)

    private func accountDetailSheet(for initialAccount: AccountItem) -> some View {
        let liveAccount = store.accounts.first(where: { $0.id == initialAccount.id }) ?? initialAccount
        let auditLogs = store.auditLogs(for: liveAccount.name)
        let bills = store.transactions.filter { tx in
            let isSource = tx.accountId == liveAccount.id
                || tx.accountName == liveAccount.name
            let isTarget = tx.targetAccountId == liveAccount.id
                || tx.targetAccountName == liveAccount.name
            return isSource || isTarget
        }

        return ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    // Gold cream account header: icon · name · 自定义余额 · … / 余额 / 记账·转账
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            MimiStickerIconView(
                                iconName: liveAccount.iconName,
                                categoryName: liveAccount.name,
                                transactionType: .income,
                                size: 44
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(liveAccount.name)
                                    .mimiFont(17, weight: .bold)
                                    .foregroundColor(MimiTheme.textPrimary)
                                Text(liveAccount.subtitle.isEmpty ? "自定义余额" : liveAccount.subtitle)
                                    .mimiFont(12)
                                    .foregroundColor(MimiTheme.textSecondary)
                            }
                            Spacer()
                            Button {
                                editAccountRoute = EditAccountSheetRoute(accountId: liveAccount.id)
                            } label: {
                                Image(systemName: "ellipsis")
                                    .mimiFont(14, weight: .semibold)
                                    .foregroundColor(MimiTheme.iconInactive)
                                    .frame(width: MimiHIG.minTouch, height: MimiHIG.minTouch)
                                    .contentShape(Rectangle())
                            }
                            .mimiPressable()
                            .accessibilityLabel(MimiL10n.string("编辑账户"))
                            .accessibilityHint(MimiL10n.string("修改名称、图标与账户设置"))
                        }

                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 0.5))
                            path.addLine(to: CGPoint(x: 2000, y: 0.5))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundColor(MimiTheme.assetAccent)
                        .frame(height: 1)
                        .clipped()

                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("余额", bundle: .mimiModule)
                                    .mimiFont(12)
                                    .foregroundColor(MimiTheme.textSecondary)
                                HStack(spacing: 6) {
                                    Text(MimiTheme.formatRM(liveAccount.balance))
                                        .mimiFont(28, weight: .bold, design: .rounded)
                                        .foregroundColor(liveAccount.balance < -0.0001 ? MimiTheme.dangerEmphasis : MimiTheme.textPrimary)
                                    Button {
                                        if !showBalanceEditSheet {
                                            let mode = AccountBalanceEditPrefill.Mode(rawValue: balanceEditMode) ?? .setOpening
                                            newBalanceInput = AccountBalanceEditPrefill.formattedInput(
                                                mode: mode,
                                                balance: liveAccount.balance,
                                                initialBalance: liveAccount.initialBalance
                                            )
                                        }
                                        showBalanceEditSheet.toggle()
                                    } label: {
                                        Image(systemName: "pencil")
                                            .mimiFont(13, weight: .semibold)
                                            .foregroundColor(MimiTheme.iconInactive)
                                    }
                                    .mimiPressable()
                                    .accessibilityLabel("编辑余额")
                                }
                            }
                            Spacer()
                        }

                        if showBalanceEditSheet {
                            VStack(alignment: .leading, spacing: 8) {
                                Picker("设置类型", selection: $balanceEditMode) {
                                    Text("设定期初资金(记账前)", bundle: .mimiModule).tag(AccountBalanceEditPrefill.Mode.setOpening.rawValue)
                                    Text("校准当前余额(手机银行)", bundle: .mimiModule).tag(AccountBalanceEditPrefill.Mode.calibrateCurrent.rawValue)
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: balanceEditMode) { _, newMode in
                                    let mode = AccountBalanceEditPrefill.Mode(rawValue: newMode) ?? .setOpening
                                    newBalanceInput = AccountBalanceEditPrefill.formattedInput(
                                        mode: mode,
                                        balance: liveAccount.balance,
                                        initialBalance: liveAccount.initialBalance
                                    )
                                }

                                HStack(spacing: 8) {
                                    Text("RM")
                                        .mimiFont(14, weight: .bold)
                                        .foregroundColor(MimiTheme.textSecondary)

                                    TextField("输入金额", text: $newBalanceInput)
                                        .mimiFont(14)
                                        .padding(8)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(MimiTheme.cardBackground))
                                        .accessibilityLabel(balanceEditMode == 0 ? "期初资金" : "当前余额")

                                    Button(MimiL10n.string("确定")) {
                                        if let val = Double(newBalanceInput) {
                                            if balanceEditMode == AccountBalanceEditPrefill.Mode.setOpening.rawValue {
                                                store.setAccountInitialBalance(accountId: liveAccount.id, initialBalance: val)
                                            } else {
                                                store.updateAccountBalance(accountId: liveAccount.id, newBalance: val)
                                            }
                                        }
                                        showBalanceEditSheet = false
                                    }
                                    .mimiFont(13, weight: .bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(MimiTheme.expenseBlue))
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            accountActionPill(title: "记账", systemName: "plus") {
                                showBalanceEditSheet = false
                                dispatch(.openEntry(.expense(accountName: liveAccount.name)))
                            }
                            accountActionPill(title: "转账", systemName: "arrow.left.arrow.right") {
                                showBalanceEditSheet = false
                                dispatch(.openEntry(.transfer(accountName: liveAccount.name)))
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(MimiTheme.assetCream)
                    )

                    HStack {
                        Text("账户明细", bundle: .mimiModule)
                            .mimiFont(15, weight: .bold)
                            .foregroundColor(MimiTheme.textPrimary)
                        Spacer()
                        HStack(spacing: 0) {
                            ForEach(
                                [("明细", "calendar"), ("账单", "doc.text")],
                                id: \.0
                            ) { tab, icon in
                                Button {
                                    detailTabMode = tab
                                } label: {
                                    Image(systemName: icon)
                                        .mimiFont(13, weight: .semibold)
                                        .foregroundColor(detailTabMode == tab ? MimiTheme.expenseBlue : MimiTheme.textMuted)
                                        .frame(width: 36, height: 28)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(detailTabMode == tab ? MimiTheme.tintBlueChip : Color.clear)
                                        )
                                }
                                .mimiPressable()
                                .accessibilityLabel(tab)
                            }
                        }
                        .padding(3)
                        .background(RoundedRectangle(cornerRadius: 10).fill(MimiTheme.fillSubtle))
                    }

                    if detailTabMode == "明细" {
                        accountAuditSection(logs: auditLogs, account: liveAccount)
                    } else {
                        accountBillsSection(bills: bills, account: liveAccount)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        .background(MimiTheme.background.ignoresSafeArea())
        .navigationTitle(MimiL10n.string("账户详情"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationBarBackButtonHidden(true)
        .mimiInteractivePopGestureEnabled()
        .mimiEdgeSwipeBack {
            dispatch(.back)
        }
        .toolbar {
            // Same leading placement as assets root, but action goes through nav.back
            // so left→right→left only pops detail — never the 资产 overlay.
            // Edge-swipe-back restored via mimiInteractivePopGestureEnabled (hidden system back).
            ToolbarItem(placement: backToolbarPlacement) {
                Button {
                    dispatch(.back)
                } label: {
                    Image(systemName: "chevron.left")
                        .mimiFont(15, weight: .semibold)
                        .foregroundColor(MimiTheme.textPrimary)
                        .frame(width: MimiHIG.minTouch, height: MimiHIG.minTouch)
                        .contentShape(Rectangle())
                }
                .mimiPressable()
                .accessibilityLabel(MimiL10n.string("返回资产"))
                .accessibilityHint(MimiL10n.string("返回账户列表，不会退出到记账首页"))
            }
        }
    }

    private func accountActionPill(title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                    .mimiFont(12, weight: .semibold)
                Text(title)
                    .mimiFont(14, weight: .semibold)
            }
            .foregroundColor(MimiTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Capsule().fill(MimiTheme.cardBackground))
        }
        .mimiPressable()
    }

    private func auditTypeLabel(_ log: AccountAuditLog) -> String {
        let kind: String
        switch log.transactionType {
        case .income: kind = "收入"
        case .expense: kind = "支出"
        case .transfer: kind = "转账"
        }
        return "\(kind) | \(log.categoryTitle)"
    }

    private func formattedBillDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: date)
    }

    private func isOutflow(_ tx: TransactionItem, for account: AccountItem) -> Bool {
        if tx.type == .expense { return true }
        if tx.type == .income { return false }
        // transfer: 本账户为转出 → 流出；转入 → 流入
        let isSource = tx.accountId == account.id || tx.accountName == account.name
        return isSource
    }

    /// Live 「初始余额」footer — reads `account.initialBalance` from store (updates after 设定期初).
    @ViewBuilder
    private func accountInitialBalanceFooter(for account: AccountItem) -> some View {
        let startDate = AccountInitialBalanceRowBuilder.resolveStartDate(
            for: account,
            auditLogs: store.auditLogs(for: account.name)
        )
        let row = AccountInitialBalanceRowBuilder.make(from: account, startDate: startDate)
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "flag")
                .mimiFont(14, weight: .semibold)
                .foregroundColor(MimiTheme.textMuted)
                .frame(width: 36, height: 36)
                .background(Circle().fill(MimiTheme.fillSubtle))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(row.title), bundle: .mimiModule)
                    .mimiFont(15, weight: .semibold)
                    .foregroundColor(MimiTheme.textPrimary)
                if let start = row.startDateText {
                    Text(start)
                        .mimiFont(12)
                        .foregroundColor(MimiTheme.textMuted)
                }
            }
            Spacer(minLength: 8)
            Text(row.formattedAmount)
                .mimiFont(15, weight: .bold, design: .rounded)
                .foregroundColor(MimiTheme.textSecondary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: MimiHIG.minTouch)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MimiTheme.cardBackground)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            row.startDateText.map { "\(MimiL10n.string(row.title)) \($0) \(row.formattedAmount)" }
                ?? "\(MimiL10n.string(row.title)) \(row.formattedAmount)"
        )
    }

    @ViewBuilder
    private func accountAuditSection(logs: [AccountAuditLog], account: AccountItem) -> some View {
        let monthGroups: [(key: String, title: String, items: [AccountAuditLog])] = {
            let dict = Dictionary(grouping: logs) { monthKey(from: $0.billDate) }
            return dict.keys.sorted {
                let a = $0.split(separator: "-").compactMap { Int($0) }
                let b = $1.split(separator: "-").compactMap { Int($0) }
                let ay = a.first ?? 0, am = a.count > 1 ? a[1] : 0
                let by = b.first ?? 0, bm = b.count > 1 ? b[1] : 0
                if ay != by { return ay > by }
                return am > bm
            }.map { key in
                let parts = key.split(separator: "-").compactMap { Int($0) }
                let title = monthTitle(year: parts.first ?? 0, month: parts.count > 1 ? parts[1] : 0)
                let items = (dict[key] ?? []).sorted { $0.loggedAt > $1.loggedAt }
                return (key, title, items)
            }
        }()

        VStack(alignment: .leading, spacing: 14) {
            if monthGroups.isEmpty {
                Text("暂无明细", bundle: .mimiModule)
                    .mimiFont(13)
                    .foregroundColor(MimiTheme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(RoundedRectangle(cornerRadius: 18).fill(MimiTheme.cardBackground))
            } else {
                ForEach(monthGroups, id: \.key) { group in
                    let auditKey = "audit-\(group.key)"
                    let expanded = isMonthExpanded(auditKey)
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            toggleMonthExpanded(auditKey)
                        } label: {
                            HStack(spacing: 8) {
                                Text(group.title)
                                    .mimiFont(14, weight: .bold)
                                    .foregroundColor(MimiTheme.textPrimary)
                                Spacer(minLength: 8)
                                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                                    .mimiFont(11, weight: .bold)
                                    .foregroundColor(MimiTheme.textMuted)
                            }
                            .frame(minHeight: MimiHIG.minTouch)
                            .contentShape(Rectangle())
                        }
                        .mimiPressable()
                        .accessibilityLabel(group.title)
                        .accessibilityHint(expanded ? "点按收起该月" : "点按展开该月")
                        if expanded {
                            VStack(spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, log in
                                    Button {
                                        if let tx = store.transaction(forAuditLog: log) {
                                            billForDetail = tx
                                        }
                                    } label: {
                                        HStack(alignment: .top, spacing: 10) {
                                            Text(formattedBillTime(log.loggedAt))
                                                .mimiFont(12, weight: .medium, design: .rounded)
                                                .foregroundColor(MimiTheme.textMuted)
                                                .frame(width: 36, alignment: .leading)

                                            VStack(spacing: 0) {
                                                Text(log.action.rawValue)
                                                    .mimiFont(10, weight: .bold)
                                                    .foregroundColor(.white)
                                                    .frame(width: 22, height: 22)
                                                    .background(Circle().fill(badgeColor(for: log.action)))
                                                if idx < group.items.count - 1 {
                                                    Rectangle()
                                                        .fill(MimiTheme.divider)
                                                        .frame(width: 1)
                                                        .frame(maxHeight: .infinity)
                                                }
                                            }
                                            .frame(width: 22)

                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(auditTypeLabel(log))
                                                    .mimiFont(13, weight: .semibold)
                                                    .foregroundColor(MimiTheme.textPrimary)
                                                if !log.note.isEmpty {
                                                    Text(log.note)
                                                        .mimiFont(12)
                                                        .foregroundColor(MimiTheme.textSecondary)
                                                        .lineLimit(2)
                                                }
                                                HStack(spacing: 4) {
                                                    Image(systemName: "calendar")
                                                        .mimiFont(10)
                                                    Text("账单日期 \(formattedBillDate(log.billDate))")
                                                        .mimiFont(11)
                                                }
                                                .foregroundColor(MimiTheme.textMuted)
                                            }

                                            Spacer(minLength: 6)

                                            VStack(alignment: .trailing, spacing: 3) {
                                                Text("余额: \(MimiTheme.formatRM(log.balanceAfter))")
                                                    .mimiFont(11, design: .rounded)
                                                    .foregroundColor(MimiTheme.textMuted)
                                                Text(
                                                    log.deltaAmount >= 0
                                                        ? MimiTheme.formatRM(log.deltaAmount)
                                                        : "-\(MimiTheme.formatRM(abs(log.deltaAmount)))"
                                                )
                                                .mimiFont(15, weight: .bold, design: .rounded)
                                                .strikethrough(log.action == .deleted && log.deltaAmount < 0, color: MimiTheme.textMuted)
                                                .foregroundColor(
                                                    log.action == .deleted && log.deltaAmount < 0
                                                        ? MimiTheme.textMuted
                                                        : (log.deltaAmount >= 0 ? MimiTheme.incomeOrange : MimiTheme.expenseBlue)
                                                )
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .contentShape(Rectangle())
                                    }
                                    .mimiPressable()
                                    .disabled(store.transaction(forAuditLog: log) == nil)
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 18).fill(MimiTheme.cardBackground))
                        }
                    }
                }
            }
            // Starting marker under oldest entries (list is newest-first).
            accountInitialBalanceFooter(for: account)
        }
    }

    @ViewBuilder
    private func accountBillsSection(bills: [TransactionItem], account: AccountItem) -> some View {
        let cal = Calendar(identifier: .gregorian)
        let monthGroups: [(key: String, title: String, items: [TransactionItem])] = {
            let dict = Dictionary(grouping: bills) { monthKey(from: $0.date) }
            return dict.keys.sorted {
                let a = $0.split(separator: "-").compactMap { Int($0) }
                let b = $1.split(separator: "-").compactMap { Int($0) }
                let ay = a.first ?? 0, am = a.count > 1 ? a[1] : 0
                let by = b.first ?? 0, bm = b.count > 1 ? b[1] : 0
                if ay != by { return ay > by }
                return am > bm
            }.map { key in
                let parts = key.split(separator: "-").compactMap { Int($0) }
                let title = monthTitle(year: parts.first ?? 0, month: parts.count > 1 ? parts[1] : 0)
                let items = (dict[key] ?? []).sorted { $0.date > $1.date }
                return (key, title, items)
            }
        }()

        VStack(alignment: .leading, spacing: 16) {
            if monthGroups.isEmpty {
                Text("暂无账单", bundle: .mimiModule)
                    .mimiFont(13)
                    .foregroundColor(MimiTheme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(RoundedRectangle(cornerRadius: 16).fill(MimiTheme.cardBackground))
            } else {
                ForEach(monthGroups, id: \.key) { month in
                    let outflow = month.items.filter { isOutflow($0, for: account) }.reduce(0.0) { $0 + $1.amount }
                    let inflow = month.items.filter { !isOutflow($0, for: account) }.reduce(0.0) { $0 + $1.amount }
                    let dayGrouped: [(key: DateComponents, items: [TransactionItem])] = {
                        let dict = Dictionary(grouping: month.items) { tx in
                            cal.dateComponents([.year, .month, .day], from: tx.date)
                        }
                        return dict.keys.sorted {
                            let a = cal.date(from: $0) ?? .distantPast
                            let b = cal.date(from: $1) ?? .distantPast
                            return a > b
                        }.map { ($0, (dict[$0] ?? []).sorted { $0.date > $1.date }) }
                    }()

                    let billsKey = "bills-\(month.key)"
                    let expanded = isMonthExpanded(billsKey)
                    VStack(alignment: .leading, spacing: 10) {
                        // Gold: 2026年11月 · 流出 · 流入 · ∨ (chevron on the far right)
                        Button {
                            toggleMonthExpanded(billsKey)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(month.title)
                                    .mimiFont(15, weight: .bold)
                                    .foregroundColor(MimiTheme.textPrimary)
                                Spacer(minLength: 6)
                                Text("流出 \(MimiTheme.formatRM(outflow))")
                                    .mimiFont(12, weight: .semibold, design: .rounded)
                                    .foregroundColor(MimiTheme.expenseBlue)
                                Text("流入 \(MimiTheme.formatRM(inflow))")
                                    .mimiFont(12, weight: .semibold, design: .rounded)
                                    .foregroundColor(MimiTheme.incomeOrange)
                                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                                    .mimiFont(11, weight: .bold)
                                    .foregroundColor(MimiTheme.textMuted)
                            }
                            .frame(minHeight: MimiHIG.minTouch)
                            .contentShape(Rectangle())
                        }
                        .mimiPressable()
                        .accessibilityLabel("\(month.title)，流出 \(MimiTheme.formatRM(outflow))，流入 \(MimiTheme.formatRM(inflow))")
                        .accessibilityHint(expanded ? "点按收起该月账单" : "点按展开该月账单")

                        if expanded {
                            ForEach(Array(dayGrouped.enumerated()), id: \.offset) { _, group in
                                let dayDate = cal.date(from: group.key) ?? Date()
                                let weekday = cal.component(.weekday, from: dayDate)
                                let weekdayMap = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
                                let dayLabel = String(
                                    format: "%d月%d日 (%@)",
                                    group.key.month ?? 0,
                                    group.key.day ?? 0,
                                    (weekday >= 1 && weekday <= 7) ? weekdayMap[weekday] : ""
                                )

                                VStack(alignment: .leading, spacing: 0) {
                                    Text(dayLabel)
                                        .mimiFont(13, weight: .semibold)
                                        .foregroundColor(MimiTheme.textSecondary)
                                        .padding(.horizontal, 14)
                                        .padding(.top, 12)
                                        .padding(.bottom, 4)

                                    ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, tx in
                                        Button {
                                            billForDetail = tx
                                        } label: {
                                            HStack(alignment: .top, spacing: 12) {
                                                MimiStickerIconView(
                                                    iconName: tx.iconName,
                                                    categoryName: tx.categoryPath,
                                                    transactionType: tx.type,
                                                    size: 36
                                                )
                                                VStack(alignment: .leading, spacing: 4) {
                                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                        Text(billCategoryTitle(for: tx))
                                                            .mimiFont(15, weight: .semibold)
                                                            .foregroundColor(MimiTheme.textPrimary)
                                                            .lineLimit(1)
                                                        Spacer(minLength: 8)
                                                        let rowOut = isOutflow(tx, for: account)
                                                        Text(rowOut
                                                             ? "-\(MimiTheme.formatRM(tx.amount))"
                                                             : "+\(MimiTheme.formatRM(tx.amount))")
                                                            .mimiFont(15, weight: .bold, design: .rounded)
                                                            .foregroundColor(rowOut
                                                                             ? MimiTheme.expenseBlue
                                                                             : MimiTheme.incomeOrange)
                                                    }
                                                    Text(billSecondaryLine(for: tx))
                                                        .mimiFont(12)
                                                        .foregroundColor(MimiTheme.textMuted)
                                                        .lineLimit(2)
                                                    // Account chip — gold shows source/target account name
                                                    Text({
                                                        if tx.type == .transfer {
                                                            let other = isOutflow(tx, for: account)
                                                                ? (tx.targetAccountName ?? store.accountName(for: tx.targetAccountId))
                                                                : store.accountName(for: tx.accountId)
                                                            return other
                                                        }
                                                        return store.accountName(for: tx.accountId)
                                                    }())
                                                        .mimiFont(11, weight: .medium)
                                                        .foregroundColor(MimiTheme.textSecondary)
                                                        .padding(.horizontal, 7)
                                                        .padding(.vertical, 3)
                                                        .background(Capsule().fill(MimiTheme.fillSubtle))
                                                }
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .contentShape(Rectangle())
                                        }
                                        .mimiPressable()
                                        .accessibilityLabel("\(billCategoryTitle(for: tx)) \(billSecondaryLine(for: tx))")
                                        if idx < group.items.count - 1 {
                                            Divider().padding(.leading, 62)
                                        }
                                    }
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(MimiTheme.cardBackground)
                                )
                            }
                        }
                    }
                }
            }
            // Starting marker under oldest bills (newest-first list → bottom = before first chronological bill).
            accountInitialBalanceFooter(for: account)
        }
    }

    private func formattedBillTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func badgeColor(for action: AuditActionType) -> Color {
        switch action {
        case .created:
            return MimiTheme.expenseBlue
        case .updated:
            return MimiTheme.incomeOrange
        case .deleted:
            return MimiTheme.dangerRed
        }
    }
}
