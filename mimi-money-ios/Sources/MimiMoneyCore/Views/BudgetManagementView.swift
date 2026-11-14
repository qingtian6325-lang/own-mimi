import SwiftUI

public struct BudgetManagementView: View {
    @ObservedObject public var store: MimiStore
    public var onDismiss: () -> Void

    @State private var showDynamicDailySheet: Bool = false
    private enum ActiveBudgetSheetType: Identifiable {
        case editTotal
        case editCategory(CategoryBudgetItem)
        case addCategory(CategoryGroup)
        case selectNewCategory

        var id: String {
            switch self {
            case .editTotal: return "total"
            case .editCategory(let c): return "edit_\(c.categoryName)"
            case .addCategory(let g): return "add_\(g.name)"
            case .selectNewCategory: return "select_new"
            }
        }
    }

    @State private var activeSheetType: ActiveBudgetSheetType? = nil
    @State private var totalBudgetInput: String = ""
    @State private var categoryBudgetInput: String = ""
    @State private var newCategoryBudgetInput: String = ""
    @State private var selectedDayKeyForCustomBudget: String?
    @State private var customDayBudgetInput: String = ""
    @State private var categoryBudgetsExpanded: Bool = true
    @State private var historyCategory: CategoryBudgetItem? = nil
    @State private var historyMonthDrill: CategoryMonthDrill? = nil
    @State private var historyBillForDetail: TransactionItem? = nil
    @State private var selectedDynamicDay: Int? = nil
    @State private var dynamicDayBillForDetail: TransactionItem? = nil

    private struct CategoryMonthDrill: Identifiable, Hashable {
        let categoryName: String
        let year: Int
        let month: Int
        var id: String { "\(categoryName)-\(year)-\(month)" }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(store: MimiStore, onDismiss: @escaping () -> Void) {
        self.store = store
        self.onDismiss = onDismiss
    }

    private var currentPeriod: BillingPeriod { store.currentBillingPeriod() }

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

    private var dailyAvailable: Double {
        store.dailyAvailableBudget()
    }

    private var todaySpent: Double {
        let cal = Calendar(identifier: .gregorian)
        let todayStart = cal.startOfDay(for: Date())
        return store.transactions
            .filter { tx in
                guard tx.type == .expense && tx.includeInStats else { return false }
                return cal.startOfDay(for: tx.date) == todayStart
            }
            .reduce(0.0) { $0 + $1.amount }
    }

    private var todayRemainingAvailable: Double {
        max(0.0, dailyAvailable - todaySpent)
    }

    private var categorizedBudgetTotal: Double {
        store.categoryBudgets.reduce(0.0) { $0 + $1.monthlyLimit }
    }

    /// 已分类预算：使用巴仙高 → 低。
    private var sortedCategoryBudgetsByUsage: [CategoryBudgetItem] {
        CategoryBudgetUsageSort.sortedByUsageDescending(store.categoryBudgets) { item in
            store.categorySpent(for: item.categoryName, in: currentPeriod)
        }
    }

    private var unbudgetedCategories: [CategoryGroup] {
        let budgetedNames = Set(store.categoryBudgets.map(\.categoryName))
        return store.expenseCategories.filter { !budgetedNames.contains($0.name) }
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    monthlySummaryTopCard
                    categorizedBudgetListCard
                    dynamicDailyInlineCard
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(MimiTheme.background.ignoresSafeArea())
            .navigationTitle(MimiL10n.string("预算管理"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                            .mimiFont(15, weight: .semibold)
                            .foregroundColor(MimiTheme.textPrimary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Text("Main Ledger ⌄")
                        .mimiFont(12, weight: .semibold)
                        .foregroundColor(MimiTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(MimiTheme.cardBackground))
                }
            }
            .sheet(isPresented: $showDynamicDailySheet) {
                dynamicDailyBudgetCalendarSheet
                    .mimiInteractiveSheet()
            }
            .sheet(item: $activeSheetType) { sheetType in
                budgetModalSheet(for: sheetType)
                    .mimiInteractiveSheet(detents: [.height(340)])
            }
            .sheet(item: $historyCategory) { item in
                categoryBudgetHistorySheet(for: item)
                    .mimiInteractiveSheet()
            }
        }
        .mimiEdgeSwipeBack(onBack: onDismiss)
    }

    @ViewBuilder
    private func budgetModalSheet(for sheetType: ActiveBudgetSheetType) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                switch sheetType {
                case .editTotal:
                    Text("设置月度总预算", bundle: .mimiModule)
                        .mimiFont(18, weight: .bold)
                        .foregroundColor(MimiTheme.textPrimary)

                    Text("当前总预算为 \(MimiTheme.formatRM(store.monthlyBudgetTotal))。设置后将实时影响当月结余与日预算。")
                        .mimiFont(13)
                        .foregroundColor(MimiTheme.textSecondary)

                    HStack(spacing: 6) {
                        Text("RM")
                            .mimiFont(20, weight: .bold, design: .rounded)
                            .foregroundColor(MimiTheme.textPrimary)
                        TextField("0.00", text: $totalBudgetInput)
                            .mimiFont(24, weight: .bold, design: .rounded)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(MimiTheme.background))

                    Button {
                        if let val = Double(totalBudgetInput), val >= 0 {
                            store.updateMonthlyBudget(val)
                        }
                        activeSheetType = nil
                    } label: {
                        Text("保存总预算", bundle: .mimiModule)
                            .mimiFont(15, weight: .bold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(MimiTheme.expenseBlue))
                    }
                    .mimiPressable()

                case .editCategory(let item):
                    HStack(spacing: 10) {
                        MimiStickerIconView(
                            iconName: item.iconName,
                            categoryName: item.categoryName,
                            transactionType: .expense,
                            useFirstCharIcon: item.useFirstCharIcon,
                            size: 34
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.categoryName)
                                .mimiFont(17, weight: .bold)
                                .foregroundColor(MimiTheme.textPrimary)
                            Text("修改此分类月度支出上限", bundle: .mimiModule)
                                .mimiFont(12)
                                .foregroundColor(MimiTheme.textSecondary)
                        }
                    }

                    HStack(spacing: 6) {
                        Text("RM")
                            .mimiFont(20, weight: .bold, design: .rounded)
                            .foregroundColor(MimiTheme.textPrimary)
                        TextField("0.00", text: $categoryBudgetInput)
                            .mimiFont(24, weight: .bold, design: .rounded)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(MimiTheme.background))

                    HStack(spacing: 10) {
                        Button {
                            store.removeCategoryBudget(categoryName: item.categoryName)
                            activeSheetType = nil
                        } label: {
                            Text("删除分类预算", bundle: .mimiModule)
                                .mimiFont(14, weight: .semibold)
                                .foregroundColor(MimiTheme.dangerRed)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(MimiTheme.dangerSoft))
                        }
                        .mimiPressable()

                        Button {
                            if let val = Double(categoryBudgetInput), val >= 0 {
                                store.setCategoryBudget(categoryName: item.categoryName, monthlyLimit: val, iconName: item.iconName)
                            }
                            activeSheetType = nil
                        } label: {
                            Text("保存修改", bundle: .mimiModule)
                                .mimiFont(14, weight: .bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(MimiTheme.expenseBlue))
                        }
                        .mimiPressable()
                    }

                case .addCategory(let grp):
                    HStack(spacing: 10) {
                        MimiStickerIconView(
                            iconName: grp.displayBadgeToken,
                            categoryName: grp.name,
                            transactionType: .expense,
                            useFirstCharIcon: grp.useFirstCharIcon,
                            size: 34
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("为「\(grp.name)」添加预算")
                                .mimiFont(17, weight: .bold)
                                .foregroundColor(MimiTheme.textPrimary)
                            Text("设定该分类每月支出上限", bundle: .mimiModule)
                                .mimiFont(12)
                                .foregroundColor(MimiTheme.textSecondary)
                        }
                    }

                    HStack(spacing: 6) {
                        Text("RM")
                            .mimiFont(20, weight: .bold, design: .rounded)
                            .foregroundColor(MimiTheme.textPrimary)
                        TextField("0.00", text: $newCategoryBudgetInput)
                            .mimiFont(24, weight: .bold, design: .rounded)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(MimiTheme.background))

                    Button {
                        if let val = Double(newCategoryBudgetInput), val > 0 {
                            store.setCategoryBudget(categoryName: grp.name, monthlyLimit: val, iconName: grp.displayBadgeToken)
                        }
                        activeSheetType = nil
                    } label: {
                        Text("确定添加分类预算", bundle: .mimiModule)
                            .mimiFont(15, weight: .bold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(MimiTheme.expenseBlue))
                    }
                    .mimiPressable()

                case .selectNewCategory:
                    Text("选择要增加预算的分类", bundle: .mimiModule)
                        .mimiFont(17, weight: .bold)
                        .foregroundColor(MimiTheme.textPrimary)

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(unbudgetedCategories) { grp in
                                Button {
                                    newCategoryBudgetInput = "200.00"
                                    activeSheetType = .addCategory(grp)
                                } label: {
                                    HStack(spacing: 12) {
                                        MimiStickerIconView(
                                            iconName: grp.displayBadgeToken,
                                            categoryName: grp.name,
                                            transactionType: .expense,
                                            useFirstCharIcon: grp.useFirstCharIcon,
                                            size: 32
                                        )
                                        Text(grp.name)
                                            .mimiFont(15, weight: .medium)
                                            .foregroundColor(MimiTheme.textPrimary)
                                        Spacer()
                                        Image(systemName: "plus.circle.fill")
                                            .mimiFont(16)
                                            .foregroundColor(MimiTheme.expenseBlue)
                                    }
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(MimiTheme.background))
                                }
                                .mimiPressable()
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(MimiL10n.string("取消")) { activeSheetType = nil }
                }
            }
        }
    }

    // MARK: - Top Monthly Overview +Ring Chart (IMG_2263)

    private var budgetUsedRatio: Double {
        let total = max(store.monthlyBudgetTotal, 0.0001)
        return min(1.0, max(0.0, monthlySpent / total))
    }

    private var monthlySummaryTopCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(currentPeriod.displayRangeLabel)
                        .mimiFont(12, weight: .medium)
                        .foregroundColor(MimiTheme.textSecondary)

                    Text("月预算剩余", bundle: .mimiModule)
                        .mimiFont(13, weight: .medium)
                        .foregroundColor(MimiTheme.textSecondary)

                    Text(MimiTheme.formatRM(monthlyRemaining))
                        .mimiFont(26, weight: .bold, design: .rounded)
                        .foregroundColor(MimiTheme.textPrimary)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(MimiTheme.fillSubtle).frame(height: MimiTheme.progressBarHeight)
                            Capsule()
                                .fill(MimiTheme.expenseBlue)
                                .frame(width: max(8, geo.size.width * CGFloat(budgetUsedRatio)), height: MimiTheme.progressBarHeight)
                            Text("\(Int((budgetUsedRatio * 100).rounded()))%")
                                .mimiFont(10, weight: .bold)
                                .foregroundColor(.white)
                                .padding(.leading, 8)
                        }
                    }
                    .frame(height: MimiTheme.progressBarHeight)

                    HStack {
                        Text("已用 \(MimiTheme.formatRM(monthlySpent))")
                            .mimiFont(12)
                            .foregroundColor(MimiTheme.textSecondary)
                        Spacer()
                        Button {
                            totalBudgetInput = String(format: "%.2f", store.monthlyBudgetTotal)
                            activeSheetType = .editTotal
                        } label: {
                            HStack(spacing: 4) {
                                Text(MimiTheme.formatRM(store.monthlyBudgetTotal))
                                    .mimiFont(13, weight: .semibold, design: .rounded)
                                    .foregroundColor(MimiTheme.textPrimary)
                                Image(systemName: "pencil")
                                    .mimiFont(12, weight: .semibold)
                                    .foregroundColor(MimiTheme.expenseBlue)
                            }
                        }
                        .mimiPressable()
                        .accessibilityLabel(MimiL10n.string("修改月预算"))
                    }
                }

                Spacer(minLength: 12)

                ZStack {
                    Circle()
                        .stroke(MimiTheme.fillSubtle, lineWidth: 9)
                        .frame(width: 86, height: 86)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(1, todayRemainingAvailable / max(dailyAvailable, 0.0001))))
                        .stroke(MimiTheme.expenseBlue, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 86, height: 86)
                    VStack(spacing: 2) {
                        Text("今日可用", bundle: .mimiModule)
                            .mimiFont(9, weight: .semibold)
                            .foregroundColor(MimiTheme.expenseBlue)
                        Text(String(format: "%.2f", todayRemainingAvailable))
                            .mimiFont(14, weight: .bold, design: .rounded)
                            .foregroundColor(MimiTheme.textPrimary)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(MimiTheme.cardBackground))
    }

    // MARK: - 已分类预算 (IMG_2263: 6 configured categories)

    private var categorizedBudgetListCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("已分类预算", bundle: .mimiModule)
                    .mimiFont(15, weight: .bold)
                    .foregroundColor(MimiTheme.textPrimary)
                Spacer()
                Text(MimiTheme.formatRM(categorizedBudgetTotal))
                    .mimiFont(14, weight: .bold, design: .rounded)
                    .foregroundColor(MimiTheme.textPrimary)
                Button {
                    activeSheetType = .selectNewCategory
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .mimiFont(18)
                        .foregroundColor(MimiTheme.expenseBlue)
                }
                .mimiPressable()
            }

            if categoryBudgetsExpanded {
                ForEach(sortedCategoryBudgetsByUsage) { item in
                    let spent = store.categorySpent(for: item.categoryName, in: currentPeriod)
                    let rem = item.monthlyLimit - spent
                    let ratio = item.monthlyLimit > 0 ? min(1.0, spent / item.monthlyLimit) : 0

                    Button {
                        historyCategory = item
                    } label: {
                        VStack(spacing: 8) {
                            HStack(spacing: 10) {
                                MimiStickerIconView(
                                    iconName: item.iconName,
                                    categoryName: item.categoryName,
                                    transactionType: .expense,
                                    useFirstCharIcon: item.useFirstCharIcon,
                                    size: 34
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.categoryName)
                                        .mimiFont(14, weight: .semibold)
                                        .foregroundColor(MimiTheme.textPrimary)
                                    Text("已用\(MimiTheme.formatRM(spent)) | \(MimiTheme.formatRM(item.monthlyLimit))")
                                        .mimiFont(12, design: .rounded)
                                        .foregroundColor(MimiTheme.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .mimiFont(11, weight: .semibold)
                                    .foregroundColor(MimiTheme.textMuted)
                            }

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(MimiTheme.fillSubtle)
                                        .frame(height: 8)
                                    Capsule()
                                        .fill(rem >= 0 ? MimiTheme.expenseBlue : MimiTheme.dangerRed)
                                        .frame(width: geo.size.width * CGFloat(ratio), height: 8)
                                }
                            }
                            .frame(height: 8)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .mimiPressable()
                }
            }

            Button {
                withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                    categoryBudgetsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Spacer()
                    Text(categoryBudgetsExpanded ? "收起" : "展开")
                        .mimiFont(12, weight: .semibold)
                    Image(systemName: categoryBudgetsExpanded ? "chevron.up" : "chevron.down")
                        .mimiFont(11, weight: .bold)
                    Spacer()
                }
                .foregroundColor(MimiTheme.textSecondary)
                .padding(.top, 2)
            }
            .mimiPressable()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(MimiTheme.cardBackground))
    }

    // MARK: - 动态日预算（主页下方）

    private var dynamicDailyInlineCard: some View {
        let cells = DynamicBudgetEngine.buildMonthDayCells(
            year: currentYear,
            month: currentMonth,
            ledger: store.currentLedger,
            transactions: store.transactions
        )
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("动态日预算", bundle: .mimiModule)
                    .mimiFont(15, weight: .bold)
                    .foregroundColor(MimiTheme.textPrimary)
                Spacer()
                Button {
                    showDynamicDailySheet = true
                } label: {
                    Text("全屏", bundle: .mimiModule)
                        .mimiFont(12, weight: .semibold)
                        .foregroundColor(MimiTheme.expenseBlue)
                }
                .mimiPressable()
            }

            Text("点击查看当日花费，长按编辑日预算", bundle: .mimiModule)
                .mimiFont(12)
                .foregroundColor(MimiTheme.textMuted)

            if let editingKey = selectedDayKeyForCustomBudget {
                HStack(spacing: 8) {
                    Text("调整 \(editingKey)")
                        .mimiFont(12, weight: .semibold)
                    TextField("输入金额", text: $customDayBudgetInput)
                        .mimiFont(13)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(MimiTheme.cardBackground))
                    Button(MimiL10n.string("保存")) {
                        if let val = Double(customDayBudgetInput) {
                            store.setCustomDailyBudget(dateKey: editingKey, amount: val)
                        }
                        selectedDayKeyForCustomBudget = nil
                    }
                    .mimiFont(12, weight: .bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(MimiTheme.expenseBlue))
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(MimiTheme.tintBlueChip))
            }

            HStack(spacing: 0) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { w in
                    Text(w)
                        .mimiFont(12, weight: .medium)
                        .foregroundColor(MimiTheme.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(0..<dynamicDailyLeadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 58)
                }
                ForEach(cells) { cell in
                    dynamicDayCell(cell, isSelected: false, opensFullSheetOnTap: true)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(MimiTheme.cardBackground))
    }

    // MARK: - 分类预算历史（按月：预算 / 已用）

    private func categoryHistoryMonths(for item: CategoryBudgetItem) -> [(year: Int, month: Int, spent: Double, limit: Double)] {
        let cal = Calendar(identifier: .gregorian)
        var seen = Set<String>()
        var rows: [(year: Int, month: Int, spent: Double, limit: Double)] = []

        // Always include current month first
        let currentKey = String(format: "%04d-%02d", currentYear, currentMonth)
        seen.insert(currentKey)
        rows.append((
            year: currentYear,
            month: currentMonth,
            spent: store.categorySpent(for: item.categoryName, year: currentYear, month: currentMonth),
            limit: item.monthlyLimit
        ))

        for tx in store.transactions where tx.type == .expense {
            let primary = tx.categoryPath.components(separatedBy: "-").first ?? tx.categoryPath
            guard primary == item.categoryName else { continue }
            let y = cal.component(.year, from: tx.date)
            let m = cal.component(.month, from: tx.date)
            let key = String(format: "%04d-%02d", y, m)
            guard seen.insert(key).inserted else { continue }
            rows.append((
                year: y,
                month: m,
                spent: store.categorySpent(for: item.categoryName, year: y, month: m),
                limit: item.monthlyLimit
            ))
        }

        return rows.sorted {
            if $0.year != $1.year { return $0.year > $1.year }
            return $0.month > $1.month
        }
    }

    private func categoryBudgetHistorySheet(for item: CategoryBudgetItem) -> some View {
        let rows = categoryHistoryMonths(for: item)
        return NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        MimiStickerIconView(
                            iconName: item.iconName,
                            categoryName: item.categoryName,
                            transactionType: .expense,
                            useFirstCharIcon: item.useFirstCharIcon,
                            size: 44
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.categoryName)
                                .mimiFont(18, weight: .bold)
                                .foregroundColor(MimiTheme.textPrimary)
                            Text("当前月预算 \(MimiTheme.formatRM(item.monthlyLimit))")
                                .mimiFont(13)
                                .foregroundColor(MimiTheme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(MimiTheme.cardBackground))

                    Button {
                        categoryBudgetInput = String(format: "%.2f", item.monthlyLimit)
                        historyCategory = nil
                        withAnimation(MimiMotion.sheet(reduceMotion: reduceMotion)) {
                            activeSheetType = .editCategory(item)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "pencil")
                            Text("修改分类预算", bundle: .mimiModule)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .mimiFont(14, weight: .semibold)
                        .foregroundColor(MimiTheme.expenseBlue)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(MimiTheme.tintBlueChip))
                    }
                    .mimiPressable()

                    Text("历史月份", bundle: .mimiModule)
                        .mimiFont(13, weight: .semibold)
                        .foregroundColor(MimiTheme.textSecondary)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                            let rem = row.limit - row.spent
                            Button {
                                historyMonthDrill = CategoryMonthDrill(
                                    categoryName: item.categoryName,
                                    year: row.year,
                                    month: row.month
                                )
                            } label: {
                                HStack {
                                    Text(String(format: "%d年%d月", row.year, row.month))
                                        .mimiFont(15, weight: .semibold)
                                        .foregroundColor(MimiTheme.textPrimary)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("已用 \(MimiTheme.formatRM(row.spent))")
                                            .mimiFont(13, weight: .semibold, design: .rounded)
                                            .foregroundColor(MimiTheme.expenseBlue)
                                        Text("预算 \(MimiTheme.formatRM(row.limit))")
                                            .mimiFont(12, design: .rounded)
                                            .foregroundColor(MimiTheme.textMuted)
                                        Text(rem >= 0 ? "剩余 \(MimiTheme.formatRM(rem))" : "超支 \(MimiTheme.formatRM(abs(rem)))")
                                            .mimiFont(11)
                                            .foregroundColor(rem >= 0 ? MimiTheme.balanceGreen : MimiTheme.dangerRed)
                                    }
                                    Image(systemName: "chevron.right")
                                        .mimiFont(11, weight: .semibold)
                                        .foregroundColor(MimiTheme.textMuted)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .mimiPressable()
                            if idx < rows.count - 1 {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 16).fill(MimiTheme.cardBackground))
                }
                .padding(16)
            }
            .background(MimiTheme.background.ignoresSafeArea())
            .navigationTitle(MimiL10n.string("分类预算"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(MimiL10n.string("关闭")) {
                        historyMonthDrill = nil
                        historyCategory = nil
                    }
                }
            }
            .navigationDestination(item: $historyMonthDrill) { drill in
                CategoryBillsListView(
                    store: store,
                    categoryName: drill.categoryName,
                    transactionType: .expense,
                    year: drill.year,
                    month: drill.month,
                    onSelectTransaction: { tx in
                        historyBillForDetail = tx
                    },
                    onDismiss: {
                        historyMonthDrill = nil
                    }
                )
                .navigationBarBackButtonHidden(true)
                .mimiInteractivePopGestureEnabled()
            }
            .sheet(item: $historyBillForDetail) { tx in
                BillDetailSheetView(store: store, transaction: tx) {
                    historyBillForDetail = nil
                }
                .mimiInteractiveSheet()
            }
        }
    }

    // MARK: - 动态日预算 Calendar Sheet (gold)

    private var dynamicDailyLeadingBlanks: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday-first per gold budget calendar
        var comps = DateComponents()
        comps.year = currentYear
        comps.month = currentMonth
        comps.day = 1
        guard let first = cal.date(from: comps) else { return 0 }
        let weekday = cal.component(.weekday, from: first) // 1=Sun
        return (weekday + 5) % 7
    }

    private var dynamicDailyBudgetCalendarSheet: some View {
        let cells = DynamicBudgetEngine.buildMonthDayCells(
            year: currentYear,
            month: currentMonth,
            ledger: store.currentLedger,
            transactions: store.transactions
        )
        let activeDay = selectedDynamicDay
            ?? cells.first(where: { $0.isToday })?.day
            ?? cells.first?.day
            ?? 1

        return NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("动态日预算", bundle: .mimiModule)
                            .mimiFont(16, weight: .bold)
                            .foregroundColor(MimiTheme.textPrimary)
                        Spacer()
                        Button {
                            if let today = cells.first(where: { $0.isToday }) {
                                selectedDayKeyForCustomBudget = today.id
                                customDayBudgetInput = String(format: "%.2f", today.dynamicAvailableBudget)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil")
                                    .mimiFont(11, weight: .semibold)
                                Text("日预算设置", bundle: .mimiModule)
                                    .mimiFont(12, weight: .semibold)
                            }
                            .foregroundColor(MimiTheme.expenseBlue)
                        }
                        .mimiPressable()
                    }

                    Text("点击查看当日花费，长按编辑日预算", bundle: .mimiModule)
                        .mimiFont(12)
                        .foregroundColor(MimiTheme.textMuted)

                    if let editingKey = selectedDayKeyForCustomBudget {
                        HStack(spacing: 8) {
                            Text("调整 \(editingKey)")
                                .mimiFont(12, weight: .semibold)
                            TextField("输入金额", text: $customDayBudgetInput)
                                .mimiFont(13)
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(MimiTheme.cardBackground))
                            Button(MimiL10n.string("保存")) {
                                if let val = Double(customDayBudgetInput) {
                                    store.setCustomDailyBudget(dateKey: editingKey, amount: val)
                                }
                                selectedDayKeyForCustomBudget = nil
                            }
                            .mimiFont(12, weight: .bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(MimiTheme.expenseBlue))
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(MimiTheme.tintBlueChip))
                    }

                    VStack(spacing: 8) {
                        HStack(spacing: 0) {
                            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { w in
                                Text(w)
                                    .mimiFont(12, weight: .medium)
                                    .foregroundColor(MimiTheme.textMuted)
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                            ForEach(0..<dynamicDailyLeadingBlanks, id: \.self) { _ in
                                Color.clear.frame(height: 58)
                            }
                            ForEach(cells) { cell in
                                dynamicDayCell(cell, isSelected: cell.day == activeDay, opensFullSheetOnTap: false)
                            }
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 18).fill(MimiTheme.cardBackground))

                    // 点一天 → 下方出「全部记录」样式的当日账单
                    dynamicDayRecordsSection(day: activeDay)
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(MimiTheme.background.ignoresSafeArea())
            .navigationTitle(MimiL10n.string("动态日预算"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(MimiL10n.string("关闭")) { showDynamicDailySheet = false }
                }
            }
            .onAppear {
                if selectedDynamicDay == nil {
                    selectedDynamicDay = cells.first(where: { $0.isToday })?.day
                        ?? cells.first?.day
                }
            }
            .sheet(item: $dynamicDayBillForDetail) { tx in
                BillDetailSheetView(store: store, transaction: tx) {
                    dynamicDayBillForDetail = nil
                }
                .mimiInteractiveSheet()
            }
        }
    }

    private func dynamicDayCell(
        _ cell: CalendarDaySummary,
        isSelected: Bool,
        opensFullSheetOnTap: Bool
    ) -> some View {
        let selectedFill = MimiTheme.selectionSoft
        let todayFill = MimiTheme.expenseBlue
        let normalFill = MimiTheme.fillSubtle

        return Button {
            selectedDynamicDay = cell.day
            if opensFullSheetOnTap {
                showDynamicDailySheet = true
            }
        } label: {
            VStack(spacing: 2) {
                Text(cell.isToday ? "今" : "\(cell.day)")
                    .mimiFont(12, weight: .bold, design: .rounded)
                    .foregroundColor(cell.isToday && !isSelected ? .white : MimiTheme.textPrimary)

                if cell.isToday {
                    Text(MimiTheme.formatRM(todaySpent))
                        .mimiFont(8, weight: .semibold, design: .rounded)
                        .foregroundColor(isSelected ? MimiTheme.expenseBlue : .white.opacity(0.95))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(MimiTheme.formatRM(todayRemainingAvailable))
                        .mimiFont(8, design: .rounded)
                        .foregroundColor(isSelected ? MimiTheme.textMuted : .white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else if cell.isPast {
                    Text(String(format: "-RM%.2f", cell.expense))
                        .mimiFont(8, weight: .semibold, design: .rounded)
                        .foregroundColor(MimiTheme.expenseBlue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    Text(MimiTheme.formatRM(cell.dynamicAvailableBudget))
                        .mimiFont(8, design: .rounded)
                        .foregroundColor(MimiTheme.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? selectedFill : (cell.isToday ? todayFill : normalFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? MimiTheme.expenseBlue : Color.clear, lineWidth: 2)
            )
        }
        .mimiPressable()
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                selectedDayKeyForCustomBudget = cell.id
                customDayBudgetInput = String(format: "%.2f", cell.dynamicAvailableBudget)
            }
        )
    }

    private func dynamicDayRecordsSection(day: Int) -> some View {
        let cal = Calendar(identifier: .gregorian)
        let txs = store.transactions.filter { tx in
            let comps = cal.dateComponents([.year, .month, .day], from: tx.date)
            return comps.year == currentYear && comps.month == currentMonth && comps.day == day
        }
        .sorted { $0.date > $1.date }
        let dayExpense = txs.filter { $0.type == .expense }.reduce(0.0) { $0 + $1.amount }
        let dayIncome = txs.filter { $0.type == .income }.reduce(0.0) { $0 + $1.amount }
        let weekdayNames = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekday: String = {
            let comps = DateComponents(year: currentYear, month: currentMonth, day: day)
            guard let date = cal.date(from: comps) else { return "" }
            let w = cal.component(.weekday, from: date)
            return (w >= 1 && w <= 7) ? weekdayNames[w] : ""
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(format: "%d月%d日 (%@)", currentMonth, day, weekday))
                    .mimiFont(13, weight: .bold)
                    .foregroundColor(MimiTheme.textPrimary)
                Spacer()
                HStack(spacing: 8) {
                    Text("支 \(MimiTheme.formatRM(dayExpense))")
                        .mimiFont(12, weight: .bold, design: .rounded)
                        .foregroundColor(MimiTheme.textPrimary)
                    Text("|")
                        .foregroundColor(Color.gray.opacity(0.3))
                    Text("收 \(MimiTheme.formatRM(dayIncome))")
                        .mimiFont(12, weight: .bold, design: .rounded)
                        .foregroundColor(MimiTheme.textSecondary)
                }
            }
            .padding(.horizontal, 2)

            if txs.isEmpty {
                Text("当日暂无记账记录", bundle: .mimiModule)
                    .mimiFont(13)
                    .foregroundColor(MimiTheme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(RoundedRectangle(cornerRadius: 16).fill(MimiTheme.cardBackground))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(txs.enumerated()), id: \.element.id) { index, item in
                        Button {
                            dynamicDayBillForDetail = item
                        } label: {
                            HStack(spacing: 12) {
                                MimiStickerIconView(
                                    iconName: item.iconName,
                                    categoryName: item.categoryPath,
                                    transactionType: item.type,
                                    size: 40
                                )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.categoryPath.components(separatedBy: "-").last ?? item.categoryPath)
                                        .mimiFont(14, weight: .semibold)
                                        .foregroundColor(MimiTheme.textPrimary)
                                    HStack(spacing: 6) {
                                        Text(dynamicDayTimeString(item.date))
                                            .mimiFont(11)
                                            .foregroundColor(MimiTheme.textMuted)
                                        if !item.note.isEmpty {
                                            Text("| \(item.note)")
                                                .mimiFont(11)
                                                .foregroundColor(MimiTheme.textSecondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    if !item.accountName.isEmpty {
                                        Text(item.accountName)
                                            .mimiFont(10, weight: .medium)
                                            .foregroundColor(MimiTheme.textSecondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(MimiTheme.fillSubtle))
                                    }
                                }
                                Spacer(minLength: 8)
                                Text(item.type == .expense || item.type == .transfer
                                     ? "-\(MimiTheme.formatRM(item.amount))"
                                     : "+\(MimiTheme.formatRM(item.amount))")
                                    .mimiFont(15, weight: .bold, design: .rounded)
                                    .foregroundColor(item.type == .expense || item.type == .transfer
                                                     ? MimiTheme.expenseDeep
                                                     : MimiTheme.incomeOrange)
                            }
                            .padding(14)
                            .contentShape(Rectangle())
                        }
                        .mimiPressable()

                        if index < txs.count - 1 {
                            Divider().padding(.leading, 66)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MimiTheme.cardBackground))
            }
        }
    }

    private func dynamicDayTimeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
