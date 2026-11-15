import SwiftUI

public struct HomeRecordView: View {
    @ObservedObject public var store: MimiStore
    public var onOpenDrawer: () -> Void
    public var onSwitchToStats: () -> Void
    public var onOpenSearchOrCalendar: () -> Void
    public var onOpenRecordSheet: (Bool) -> Void // true = AI tab, false = Manual tab
    public var onSelectTransaction: (TransactionItem) -> Void
    public var onOpenBudgetManager: () -> Void
    public var onOpenAssetsManager: () -> Void
    public var onPickFromAlbum: () -> Void = {}
    public var onTakePhoto: () -> Void = {}
    public var onOpenImportExport: () -> Void = {}

    @State private var isAmountsHidden: Bool = false
    @State private var isAskPanelExpanded: Bool = false
    @State private var isCategoryBudgetExpanded: Bool = false
    @State private var isNetWorthExpanded: Bool = true
    @State private var showLedgerSwitcherSheet: Bool = false
    @State private var showDeleteToast: Bool = false
    @State private var revealedDeleteID: UUID? = nil
    @State private var pendingDeleteID: UUID? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var deleteToastToken: UUID = UUID()
    @State private var rowSwipeConsumedTap: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        store: MimiStore,
        onOpenDrawer: @escaping () -> Void,
        onSwitchToStats: @escaping () -> Void,
        onOpenSearchOrCalendar: @escaping () -> Void,
        onOpenRecordSheet: @escaping (Bool) -> Void,
        onSelectTransaction: @escaping (TransactionItem) -> Void,
        onOpenBudgetManager: @escaping () -> Void,
        onOpenAssetsManager: @escaping () -> Void,
        onPickFromAlbum: @escaping () -> Void = {},
        onTakePhoto: @escaping () -> Void = {},
        onOpenImportExport: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onOpenDrawer = onOpenDrawer
        self.onSwitchToStats = onSwitchToStats
        self.onOpenSearchOrCalendar = onOpenSearchOrCalendar
        self.onOpenRecordSheet = onOpenRecordSheet
        self.onSelectTransaction = onSelectTransaction
        self.onOpenBudgetManager = onOpenBudgetManager
        self.onOpenAssetsManager = onOpenAssetsManager
        self.onPickFromAlbum = onPickFromAlbum
        self.onTakePhoto = onTakePhoto
        self.onOpenImportExport = onOpenImportExport
    }

    private var currentPeriod: BillingPeriod {
        store.currentBillingPeriod()
    }

    private var currentYear: Int {
        Calendar(identifier: .gregorian).component(.year, from: currentPeriod.start)
    }

    private var currentMonth: Int {
        Calendar(identifier: .gregorian).component(.month, from: currentPeriod.start)
    }

    private var monthlySpent: Double {
        store.expenseTotal(in: currentPeriod)
    }

    private var monthlyRemaining: Double {
        store.budgetRemaining(in: currentPeriod)
    }

    private var spentRatio: Double {
        guard store.monthlyBudgetTotal > 0 else { return 0 }
        return min(1.0, max(0.0, monthlySpent / store.monthlyBudgetTotal))
    }

    /// 分类预算列表：使用巴仙高 → 低。
    private var sortedCategoryBudgetsByUsage: [CategoryBudgetItem] {
        CategoryBudgetUsageSort.sortedByUsageDescending(store.categoryBudgets) { item in
            store.categorySpent(for: item.categoryName, in: currentPeriod)
        }
    }

    private var spentPercentInt: Int {
        Int((spentRatio * 100.0).rounded())
    }

    private var dailyAvailable: Double {
        store.dailyAvailableBudget()
    }

    public var body: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: MimiTheme.homeCardSpacing) {
                    monthlyBudgetCard
                    netWorthSummaryCard
                    transactionFeedSection
                }
                .padding(.horizontal, MimiTheme.homeHorizontalPadding)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                topNavigationBar
                    .padding(.horizontal, MimiTheme.homeHorizontalPadding)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity)
                    .background(MimiTheme.background)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                floatingBottomBar
                    .padding(.horizontal, MimiTheme.homeHorizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                    .background(MimiTheme.background.opacity(0.001))
            }

            if showDeleteToast {
                Text("删除成功", bundle: .mimiModule)
                    .mimiFont(15, weight: .semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.black.opacity(0.72)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .zIndex(20)
                    .allowsHitTesting(false)
            }
        }
        .background(MimiTheme.background.ignoresSafeArea())
        .sheet(isPresented: $showLedgerSwitcherSheet) {
            ledgerPickerSheet
                .mimiInteractiveSheet(detents: [.height(260)])
        }
        .alert(MimiL10n.string("确认删除这笔账单？"), isPresented: $showDeleteConfirm) {
            Button(MimiL10n.string("取消"), role: .cancel) {
                pendingDeleteID = nil
            }
            Button(MimiL10n.string("删除"), role: .destructive) {
                if let id = pendingDeleteID {
                    deleteTransactionShowingToast(id)
                }
                pendingDeleteID = nil
            }
        } message: {
            Text("删除后无法恢复", bundle: .mimiModule)
        }
    }

    // MARK: - Top Navigation Bar (gold A)

    private var topNavigationBar: some View {
        HStack(spacing: 10) {
            Button(action: onOpenDrawer) {
                Image(systemName: "line.3.horizontal")
                    .mimiFont(18, weight: .semibold)
                    .foregroundColor(MimiTheme.textPrimary)
                    .mimiMinTouchTarget()
            }
            .mimiPressable()
            .accessibilityLabel(MimiL10n.string("打开菜单"))

            Menu {
                Button {
                    // Already on 记录
                } label: {
                    Label(MimiL10n.string("记录"), systemImage: "checkmark")
                }
                .disabled(true)
                Button {
                    onSwitchToStats()
                } label: {
                    Label(MimiL10n.string("Mimi (统计与资产)"), systemImage: "chart.pie")
                }
            } label: {
                HStack(spacing: 4) {
                    Text("记录", bundle: .mimiModule)
                        .mimiFont(22, weight: .bold)
                        .foregroundColor(MimiTheme.textPrimary)
                    Image(systemName: "chevron.down")
                        .mimiFont(12, weight: .bold)
                        .foregroundColor(MimiTheme.textSecondary)
                }
            }
            .mimiPressable()
            .accessibilityLabel(MimiL10n.string("记录，切换账本视图"))

            Spacer(minLength: 8)

            Button(action: onOpenSearchOrCalendar) {
                Image(systemName: "magnifyingglass")
                    .mimiFont(15, weight: .semibold)
                    .foregroundColor(MimiTheme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(MimiTheme.cardBackground))
                    .mimiMinTouchTarget()
            }
            .mimiPressable()
            .accessibilityLabel(MimiL10n.string("搜索与日历"))

            Button {
                showLedgerSwitcherSheet = true
            } label: {
                HStack(spacing: 4) {
                    Text(store.currentLedgerName)
                        .mimiFont(14, weight: .semibold)
                        .foregroundColor(MimiTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 64, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .mimiFont(10, weight: .bold)
                        .foregroundColor(MimiTheme.textSecondary)
                }
                .padding(.leading, 12)
                .padding(.trailing, 10)
                .padding(.vertical, 8)
                .background(Capsule().fill(MimiTheme.cardBackground))
                .frame(minHeight: MimiHIG.minTouch)
            }
            .mimiPressable()
            .accessibilityLabel("当前账本 \(store.currentLedgerName)")
            .accessibilityHint(MimiL10n.string("点按切换账本"))
        }
    }

    // MARK: - Monthly Budget Card (gold A)

    private var monthlyBudgetCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Button(action: onOpenSearchOrCalendar) {
                    HStack(spacing: 4) {
                        Text("\(currentYear)年\(currentMonth)月")
                            .mimiFont(15, weight: .semibold)
                        Image(systemName: "chevron.down")
                            .mimiFont(11, weight: .bold)
                    }
                    .foregroundColor(MimiTheme.textPrimary)
                }
                .mimiPressable()

                Button(action: onSwitchToStats) {
                    HStack(spacing: 2) {
                        Text("统计", bundle: .mimiModule)
                            .mimiFont(15, weight: .semibold)
                        Image(systemName: "chevron.right")
                            .mimiFont(12, weight: .bold)
                    }
                    .foregroundColor(MimiTheme.expenseBlue)
                }
                .mimiPressable()

                Spacer(minLength: 8)
            }

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(MimiTheme.expenseBlue)
                            .frame(width: 3, height: 12)
                        Text("月预算剩余", bundle: .mimiModule)
                            .mimiFont(13, weight: .medium)
                            .foregroundColor(MimiTheme.textSecondary)
                    }
                    if store.monthStartDay != 1 {
                        Text(currentPeriod.displayRangeLabel)
                            .mimiFont(11)
                            .foregroundColor(MimiTheme.textMuted)
                    }

                    HStack(alignment: .center, spacing: 6) {
                        Button(action: onOpenBudgetManager) {
                            Text(isAmountsHidden ? "RM****" : MimiTheme.formatRM(monthlyRemaining))
                                .mimiFont(28, weight: .bold, design: .rounded)
                                .foregroundColor(MimiTheme.textPrimary)
                                .mimiAmountFit()
                        }
                        .mimiPressable()

                        Button {
                            isAmountsHidden.toggle()
                        } label: {
                            Image(systemName: isAmountsHidden ? "eye.slash" : "eye")
                                .mimiFont(14, weight: .regular)
                                .foregroundColor(MimiTheme.textMuted)
                                .mimiMinTouchTarget()
                        }
                        .mimiPressable()
                        .accessibilityLabel(isAmountsHidden ? "显示金额" : "隐藏金额")
                        .mimiPressable()
                    }

                    budgetProgressBar

                    HStack(spacing: 8) {
                        Text(isAmountsHidden ? "已用****" : "已用\(MimiTheme.formatRM(monthlySpent))")
                            .mimiFont(12)
                            .foregroundColor(MimiTheme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(isAmountsHidden ? "RM****" : MimiTheme.formatRM(store.monthlyBudgetTotal))
                            .mimiFont(12)
                            .foregroundColor(MimiTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                dailyAvailableRing
            }

            categoryBudgetSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(MimiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MimiTheme.cardCornerRadius, style: .continuous))
        .shadow(
            color: MimiTheme.homeCardShadow,
            radius: MimiTheme.homeCardShadowRadius,
            x: 0,
            y: MimiTheme.homeCardShadowY
        )
        .overlay(alignment: .topTrailing) {
            incomeExpensePill
                .padding(.trailing, 12)
                .offset(y: -12)
        }
        .padding(.top, 14)
    }

    /// Sits on the card's top-right corner, matching gold A. Opens the same calendar/search surface as the month chip.
    private var incomeExpensePill: some View {
        Button(action: onOpenSearchOrCalendar) {
            HStack(spacing: 3) {
                Image(systemName: "arrow.left.arrow.right")
                    .mimiFont(11, weight: .semibold)
                Text("收支", bundle: .mimiModule)
                    .mimiFont(13, weight: .medium)
            }
            .foregroundColor(MimiTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(MimiTheme.cardBackground))
            .overlay(Capsule().stroke(MimiTheme.divider, lineWidth: 1))
        }
        .mimiPressable()
    }

    private var budgetProgressBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let trackHeight: CGFloat = 5
            let fillWidth = min(width, max(trackHeight, width * CGFloat(spentRatio)))
            let badgeWidth: CGFloat = 36
            let badgeX = min(max(0, fillWidth - badgeWidth / 2), max(0, width - badgeWidth))
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(MimiTheme.progressTrack)
                            .frame(height: trackHeight)
                        Capsule()
                            .fill(MimiTheme.expenseBlue)
                            .frame(width: fillWidth, height: trackHeight)
                    }
                }
                Text("\(spentPercentInt)%")
                    .mimiFont(10, weight: .bold, design: .rounded)
                    .foregroundColor(MimiTheme.expenseBlue)
                    .frame(width: badgeWidth, height: 16)
                    .background(Capsule().fill(MimiTheme.tintBlueSoft))
                    .offset(x: badgeX, y: 0)
            }
        }
        .frame(height: MimiTheme.progressBarHeight)
    }

    private var dailyAvailableRing: some View {
        Button(action: onOpenBudgetManager) {
            ZStack {
                Circle()
                    .stroke(MimiTheme.fillSubtle, lineWidth: 8)
                    .frame(width: MimiTheme.dailyRingSize, height: MimiTheme.dailyRingSize)

                Circle()
                    .trim(from: 0, to: 0.92)
                    .stroke(
                        AngularGradient(
                            colors: [
                                MimiTheme.chartBlueBright,
                                MimiTheme.chartOrangeBright,
                                MimiTheme.chartTeal,
                                MimiTheme.chartPink,
                                MimiTheme.chartIndigo,
                                MimiTheme.chartBlueBright
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: MimiTheme.dailyRingSize, height: MimiTheme.dailyRingSize)

                VStack(spacing: 1) {
                    Text("今日可用", bundle: .mimiModule)
                        .mimiFont(9, weight: .medium)
                        .foregroundColor(MimiTheme.textSecondary)
                    Text(isAmountsHidden ? "****" : String(format: "%.2f", dailyAvailable))
                        .mimiFont(13, weight: .bold, design: .rounded)
                        .foregroundColor(MimiTheme.textPrimary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
            }
        }
        .mimiPressable()
        .fixedSize()
    }

    private var categoryBudgetSection: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                    isCategoryBudgetExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(MimiTheme.ringTrack, lineWidth: 3)
                            .frame(width: 16, height: 16)
                        Circle()
                            .trim(from: 0.08, to: 0.42)
                            .stroke(MimiTheme.ringProgress, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 16, height: 16)
                            .rotationEffect(.degrees(-20))
                    }
                    .frame(width: 22, height: 22)
                    HStack(spacing: 6) {
                        Text("分类预算", bundle: .mimiModule)
                            .mimiFont(14, weight: .semibold)
                            .foregroundColor(MimiTheme.textPrimary)
                        Text("共\(store.categoryBudgets.count)项")
                            .mimiFont(13)
                            .foregroundColor(MimiTheme.textMuted)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 2) {
                        Text(isCategoryBudgetExpanded ? "收起" : "展开")
                            .mimiFont(13, weight: .medium)
                        Image(systemName: isCategoryBudgetExpanded ? "chevron.up" : "chevron.down")
                            .mimiFont(11, weight: .semibold)
                    }
                    .foregroundColor(MimiTheme.expenseBlue)
                }
            }
            .mimiPressable()

            if isCategoryBudgetExpanded {
                VStack(spacing: 10) {
                    ForEach(sortedCategoryBudgetsByUsage) { item in
                        let spent = store.categorySpent(for: item.categoryName, in: currentPeriod)
                        let rem = item.monthlyLimit - spent
                        let ratio = item.monthlyLimit > 0 ? min(1.0, spent / item.monthlyLimit) : 0
                        let remLabel: String = {
                            if isAmountsHidden {
                                return rem >= 0 ? "剩余 ****" : "超支 ****"
                            }
                            return rem >= 0
                                ? "剩余 \(MimiTheme.formatRM(rem))"
                                : "超支 \(MimiTheme.formatRM(abs(rem)))"
                        }()
                        Button(action: onOpenBudgetManager) {
                            HStack(spacing: 10) {
                                MimiStickerIconView(
                                    iconName: item.iconName,
                                    categoryName: item.categoryName,
                                    transactionType: .expense,
                                    useFirstCharIcon: item.useFirstCharIcon,
                                    size: 30
                                )
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.categoryName)
                                            .mimiFont(13, weight: .medium)
                                            .foregroundColor(MimiTheme.textPrimary)
                                        Spacer()
                                        Text(remLabel)
                                            .mimiFont(12, weight: .semibold, design: .rounded)
                                            .foregroundColor(rem >= 0 ? MimiTheme.textSecondary : MimiTheme.dangerRed)
                                    }
                                    GeometryReader { barGeo in
                                        ZStack(alignment: .leading) {
                                            Capsule()
                                                .fill(MimiTheme.fillSubtle)
                                                .frame(height: 6)
                                            Capsule()
                                                .fill(rem >= 0 ? MimiTheme.expenseBlue : MimiTheme.dangerRed)
                                                .frame(width: barGeo.size.width * CGFloat(ratio), height: 6)
                                        }
                                    }
                                    .frame(height: 6)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .mimiPressable()
                        .accessibilityLabel("\(item.categoryName)预算")
                        .accessibilityHint(MimiL10n.string("打开预算管理"))
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Net Worth Card (gold A)

    private var netWorthSummaryCard: some View {
        VStack(spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                Button(action: onOpenAssetsManager) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("净资产", bundle: .mimiModule)
                            .mimiFont(13, weight: .medium)
                            .foregroundColor(MimiTheme.textSecondary)
                        Text(isAmountsHidden ? "RM****" : MimiTheme.formatRM(store.netWorth))
                            .mimiFont(22, weight: .bold, design: .rounded)
                            .foregroundColor(MimiTheme.textPrimary)
                    }
                }
                .mimiPressable()

                Spacer(minLength: 8)

                if isNetWorthExpanded {
                    Button {
                        toggleNetWorthExpanded()
                    } label: {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("30天趋势", bundle: .mimiModule)
                                .mimiFont(10, weight: .medium)
                                .foregroundColor(MimiTheme.expenseBlue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(MimiTheme.cardBackground))
                            HomeNetWorthSparkline(samples: store.netWorthSparklineSamples())
                                .frame(width: 124, height: 32)
                        }
                    }
                    .mimiPressable()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }

            Button {
                toggleNetWorthExpanded()
            } label: {
                Image(systemName: isNetWorthExpanded ? "chevron.up" : "chevron.down")
                    .mimiFont(11, weight: .bold)
                    .foregroundColor(MimiTheme.textMuted.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
            }
            .mimiPressable()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(
            RoundedRectangle(cornerRadius: MimiTheme.cardCornerRadius, style: .continuous)
                .fill(MimiTheme.netWorthCard)
        )
    }

    private func toggleNetWorthExpanded() {
        withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
            isNetWorthExpanded.toggle()
        }
    }

    // MARK: - Daily Grouped Transaction Feed (gold C/D)

    private var transactionFeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button(action: onOpenSearchOrCalendar) {
                    HStack(spacing: 2) {
                        Text("记录明细", bundle: .mimiModule)
                            .mimiFont(16, weight: .bold)
                        Image(systemName: "chevron.right")
                            .mimiFont(12, weight: .bold)
                            .padding(.top, 1)
                    }
                    .foregroundColor(MimiTheme.textPrimary)
                }
                .mimiPressable()
                .accessibilityLabel(MimiL10n.string("记录明细"))

                Spacer(minLength: 8)

                FeedBillMarkButton(action: onOpenSearchOrCalendar)
            }
            .padding(.top, 2)

            let groups = store.groupedTransactionsByDay()
            if groups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "pawprint.fill")
                        .mimiFont(34)
                        .foregroundColor(MimiTheme.incomeOrange)
                        .accessibilityHidden(true)
                    Text("还没有账单记录，点击下方 + 或发送一句话记账吧", bundle: .mimiModule)
                        .mimiFont(13)
                        .foregroundColor(MimiTheme.textMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(RoundedRectangle(cornerRadius: MimiTheme.cardCornerRadius).fill(MimiTheme.cardBackground))
            } else {
                // Stable day ids — avoid offset-based ForEach rebuild hitch on swipe-delete.
                ForEach(groups, id: \.date) { group in
                    dayTransactionGroupCard(date: group.date, items: group.items)
                }
            }
        }
    }

    /// 往左滑：只挪这一笔账单，右侧露出删除；点图标 → 确认弹窗 → 确认才删。
    private func dayTransactionGroupCard(date: Date, items: [TransactionItem]) -> some View {
        let cardRadius = MimiTheme.cardCornerRadius

        return VStack(spacing: 0) {
            dayFeedHeader(date: date, items: items)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipShape(feedCardEndClip(radius: cardRadius, top: true))

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let isLast = index == items.count - 1
                let revealed = revealedDeleteID == item.id
                ZStack(alignment: .trailing) {
                    if revealed {
                        deleteTrashButton(id: item.id)
                            .padding(.trailing, 10)
                            .transition(.scale.combined(with: .opacity))
                    }

                    feedRowButton(item, showsDivider: !isLast)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipShape(feedCardEndClip(radius: cardRadius, bottom: isLast))
                        .offset(x: revealed ? -(FeedDeleteChrome.gap + FeedDeleteChrome.side) : 0)
                }
                .clipped()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .fill(MimiTheme.cardBackground)
        )
        .animation(MimiMotion.quick(reduceMotion: reduceMotion), value: revealedDeleteID)
    }

    private func feedCardEndClip(radius: CGFloat, top: Bool = false, bottom: Bool = false) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: top ? radius : 0,
            bottomLeadingRadius: bottom ? radius : 0,
            bottomTrailingRadius: bottom ? radius : 0,
            topTrailingRadius: top ? radius : 0,
            style: .continuous
        )
    }

    private func dayFeedHeader(date: Date, items: [TransactionItem]) -> some View {
        let dayExpense = items.filter { $0.type == .expense }.reduce(0.0) { $0 + $1.amount }
        let dayIncome = items.filter { $0.type == .income }.reduce(0.0) { $0 + $1.amount }

        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(formatDayHeader(date))
                .mimiFont(14, weight: .semibold)
                .foregroundColor(MimiTheme.textPrimary)
            Spacer(minLength: 8)
            Text("支 \(MimiTheme.formatRM(dayExpense)) | 收 \(MimiTheme.formatRM(dayIncome))")
                .mimiFont(12, weight: .medium)
                .foregroundColor(MimiTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(MimiTheme.fillSubtle)
    }

    private func feedRowButton(_ item: TransactionItem, showsDivider: Bool) -> some View {
        let revealed = revealedDeleteID == item.id
        return Button {
            if rowSwipeConsumedTap {
                rowSwipeConsumedTap = false
                return
            }
            if revealedDeleteID != nil {
                dismissRevealedDelete()
                return
            }
            onSelectTransaction(item)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                if !revealed {
                    MimiStickerIconView(
                        iconName: item.iconName,
                        categoryName: item.categoryPath,
                        transactionType: item.type,
                        size: MimiTheme.transactionRowIconSize
                    )
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(transactionTitle(item))
                            .mimiFont(16, weight: .semibold)
                            .foregroundColor(MimiTheme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(signedAmountText(item))
                            .mimiFont(16, weight: .bold, design: .rounded)
                            .foregroundColor(item.type == .expense ? MimiTheme.expenseBlue : MimiTheme.incomeOrange)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }

                    Text(transactionMetaLine(item))
                        .mimiFont(12)
                        .foregroundColor(MimiTheme.textMuted)
                        .lineLimit(1)

                    if !item.accountName.isEmpty {
                        Text(item.accountName)
                            .mimiFont(11, weight: .medium)
                            .foregroundColor(MimiTheme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(MimiTheme.pillGray))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .mimiPressable()
        .simultaneousGesture(rowSwipeGesture(for: item.id))
        .contextMenu {
            Button {
                onSelectTransaction(item)
            } label: {
                Label(MimiL10n.string("查看详情"), systemImage: "doc.text")
            }
            Button(role: .destructive) {
                pendingDeleteID = item.id
                showDeleteConfirm = true
            } label: {
                Label(MimiL10n.string("删除账单"), systemImage: "trash")
            }
        }
        .accessibilityHint(MimiL10n.string("左滑或长按可删除"))
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(MimiTheme.divider)
                    .frame(height: 0.5)
                    .padding(.leading, revealed ? 14 : 14 + MimiTheme.transactionRowIconSize + 12)
            }
        }
    }

    private func deleteTrashButton(id: UUID) -> some View {
        Button {
            pendingDeleteID = id
            showDeleteConfirm = true
        } label: {
            Image(systemName: "trash.fill")
                .mimiFont(16, weight: .semibold)
                .foregroundColor(.white)
                .frame(width: FeedDeleteChrome.side, height: FeedDeleteChrome.side)
                .background(Circle().fill(MimiTheme.dangerRed))
        }
        .mimiPressable()
        .accessibilityLabel(MimiL10n.string("删除账单"))
    }

    private func rowSwipeGesture(for id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 22, coordinateSpace: .local)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if (dx * dx + dy * dy) > 324 {
                    rowSwipeConsumedTap = true
                }
            }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if (dx * dx + dy * dy) > 324 {
                    rowSwipeConsumedTap = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 40_000_000)
                        rowSwipeConsumedTap = false
                    }
                }
                guard abs(dx) > abs(dy) else { return }
                // 往左滑 → 露出右侧删除图标；往右滑 / 轻滑回去 → 收起。不直接删除。
                if dx <= -48 {
                    animateFeedChange { revealedDeleteID = id }
                } else if dx >= 36 {
                    dismissRevealedDelete()
                }
            }
    }

    private func deleteTransactionShowingToast(_ id: UUID) {
        // Animate row removal immediately; store defers disk/full reconcile off the tap path.
        withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
            if revealedDeleteID == id {
                revealedDeleteID = nil
            }
            store.deleteTransaction(id: id)
        }
        let token = UUID()
        deleteToastToken = token
        withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
            showDeleteToast = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard deleteToastToken == token else { return }
            withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                showDeleteToast = false
            }
        }
    }

    private func dismissRevealedDelete() {
        guard revealedDeleteID != nil else { return }
        animateFeedChange { revealedDeleteID = nil }
    }

    private func animateFeedChange(_ updates: () -> Void) {
        withAnimation(MimiMotion.quick(reduceMotion: reduceMotion), updates)
    }

    private func transactionTitle(_ item: TransactionItem) -> String {
        let parts = item.categoryPath.split(separator: "-").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        if let leaf = parts.last {
            return String(leaf)
        }
        return item.categoryPath
    }

    private func signedAmountText(_ item: TransactionItem) -> String {
        let formatted = MimiTheme.formatRM(item.amount)
        return item.type == .expense ? "-\(formatted)" : "+\(formatted)"
    }

    private static let feedClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func transactionMetaLine(_ item: TransactionItem) -> String {
        let clock = Self.feedClockFormatter.string(from: item.date)
        let note = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if note.isEmpty { return clock }
        return "\(clock) | \(note)"
    }

    private func formatDayHeader(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        let weekday = cal.component(.weekday, from: date)
        let names = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let wName = (weekday >= 1 && weekday <= 7) ? names[weekday] : ""
        return "\(m)月\(d)日 (\(wName))"
    }

    // MARK: - Floating Bottom Bar (mascot + 任何事情都能问我 [＋/✕] + 展开面板)

    private var floatingBottomBar: some View {
        VStack(spacing: 0) {
            if isAskPanelExpanded {
                Button {
                    withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                        isAskPanelExpanded = false
                    }
                } label: {
                    Image(systemName: "chevron.compact.up")
                        .mimiFont(18, weight: .semibold)
                        .foregroundColor(MimiTheme.controlDisabled)
                        .frame(maxWidth: .infinity)
                        .frame(height: 18)
                        .contentShape(Rectangle())
                }
                .mimiPressable()
                .padding(.bottom, 6)
                .transition(.opacity)
            }

            HStack(spacing: 8) {
                // 点问账条：按上次习惯开 AI 小窗或手动记账
                Button {
                    if BookkeepingEntryPreference.current == .manual {
                        BookkeepingEntryPreference.rememberManual()
                        onOpenRecordSheet(false)
                    } else {
                        BookkeepingEntryPreference.rememberAI()
                        onOpenRecordSheet(true)
                    }
                } label: {
                    HStack(spacing: 8) {
                        MimiAskMascotView(size: 32)
                        Text("任何事情都能问我", bundle: .mimiModule)
                            .mimiFont(15, weight: .medium)
                            .foregroundColor(MimiTheme.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .frame(minHeight: MimiHIG.minTouch)
                }
                .mimiPressable()
                .accessibilityLabel(MimiL10n.string("问账记账"))
                .accessibilityHint(BookkeepingEntryPreference.current == .manual ? "将打开手动记账" : "将打开 AI 记账")

                // ＋：展开相册 / 拍照 / 导入导出（金标三格）
                Button {
                    withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                        isAskPanelExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isAskPanelExpanded ? "xmark" : "plus")
                        .mimiFont(isAskPanelExpanded ? 16 : 20, weight: .bold)
                        .foregroundColor(isAskPanelExpanded ? MimiTheme.textSecondary : .white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(isAskPanelExpanded ? MimiTheme.fillSubtle : MimiTheme.expenseBlue)
                                .shadow(
                                    color: isAskPanelExpanded ? Color.clear : MimiTheme.expenseBlue.opacity(0.35),
                                    radius: 8,
                                    x: 0,
                                    y: 3
                                )
                        )
                }
                .mimiPressable()
                .accessibilityLabel(isAskPanelExpanded ? "收起附件面板" : "打开相册拍照导入")
            }
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .frame(height: MimiTheme.askBarHeight)
            .background(
                RoundedRectangle(cornerRadius: MimiTheme.askBarCornerRadius, style: .continuous).fill(MimiTheme.cardBackground)
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
            )

            if isAskPanelExpanded {
                AIAttachmentPanelView(
                    onPickFromAlbum: {
                        withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                            isAskPanelExpanded = false
                        }
                        onPickFromAlbum()
                    },
                    onTakePhoto: {
                        withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                            isAskPanelExpanded = false
                        }
                        onTakePhoto()
                    },
                    onOpenImportExport: {
                        withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                            isAskPanelExpanded = false
                        }
                        onOpenImportExport()
                    }
                )
                .padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private var ledgerPickerSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("切换账本", bundle: .mimiModule)
                .mimiFont(17, weight: .bold)
                .padding(.top, 16)

            ForEach(store.ledgers) { ledger in
                Button {
                    store.currentLedgerName = ledger.name
                    showLedgerSwitcherSheet = false
                } label: {
                    HStack {
                        Image(systemName: "book.closed.fill")
                            .foregroundColor(MimiTheme.expenseBlue)
                            .accessibilityHidden(true)
                        Text(ledger.name)
                            .mimiFont(15, weight: .semibold)
                            .foregroundColor(MimiTheme.textPrimary)
                        Spacer()
                        Text(ledger.currency.rawValue)
                            .mimiFont(12)
                            .foregroundColor(MimiTheme.textMuted)
                        if store.currentLedgerName == ledger.name {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(MimiTheme.expenseBlue)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(MimiTheme.background))
                }
                .mimiPressable()
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

/// 44pt circle plus the gap that keeps it outside the day card.
private enum FeedDeleteChrome {
    static let side: CGFloat = 44
    static let gap: CGFloat = 12
}

/// White chip with a blue bill mark, matching the gold feed header control.
private struct FeedBillMarkButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(MimiTheme.cardBackground)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                ZStack {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(MimiTheme.expenseBlue, lineWidth: 1.3)
                        .frame(width: 16, height: 11)
                    Circle()
                        .stroke(MimiTheme.expenseBlue, lineWidth: 1)
                        .frame(width: 8, height: 8)
                    Image(systemName: "yensign")
                        .mimiFont(6, weight: .bold)
                        .foregroundColor(MimiTheme.expenseBlue)
                }
            }
            .frame(width: 32, height: 32)
        }
        .mimiPressable()
        .accessibilityLabel(MimiL10n.string("全部记录"))
    }
}

/// Line sparkline for home「30天趋势」using live net-worth samples.
private struct HomeNetWorthSparkline: View {
    var samples: [CGFloat]

    var body: some View {
        GeometryReader { geo in
            let points = samplePoints(in: geo.size)
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(
                    MimiTheme.expenseBlue,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )

                if let last = points.last {
                    Circle()
                        .fill(MimiTheme.cardBackground)
                        .overlay(Circle().stroke(MimiTheme.expenseBlue, lineWidth: 2))
                        .frame(width: 8, height: 8)
                        .position(last)
                }
            }
        }
        .accessibilityLabel(MimiL10n.string("近30天净资产趋势"))
    }

    private func samplePoints(in size: CGSize) -> [CGPoint] {
        let values = samples.isEmpty ? [0.5, 0.5] : samples
        let count = max(values.count - 1, 1)
        let inset: CGFloat = 5
        return values.enumerated().map { index, value in
            let x = inset + (size.width - inset * 2) * CGFloat(index) / CGFloat(count)
            let y = size.height - (value * (size.height - 10)) - 5
            return CGPoint(x: x, y: y)
        }
    }
}
