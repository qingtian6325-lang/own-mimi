import SwiftUI

public struct MimiStatsView: View {
    @ObservedObject public var store: MimiStore
    public var onOpenDrawer: () -> Void
    public var onSwitchToHome: () -> Void
    public var onOpenAssets: () -> Void

    @State private var selectedPeriod: String = "月" // 周 | 月 | 年 | 自定义
    @State private var selectedChartType: TransactionType = .expense
    @State private var trendMode: String = "支出" // 支出 | 收入 | 结余
    @State private var rankingMode: String = "支出" // 支出 | 收入
    @State private var isRankingExpanded: Bool = true
    @State private var selectedLedgerFilterId: String? = nil // nil = current ledger
    @State private var selectedFilterType: String = "全部" // 全部 | 仅支出 | 仅收入

    @State private var statsYear: Int = Calendar.current.component(.year, from: Date())
    @State private var statsMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var statsMonthOffset: Int = 0
    @State private var statsWeekOffset: Int = 0
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEndDate: Date = Date()

    @State private var drillCategoryName: String? = nil
    @State private var billForDetail: TransactionItem? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        store: MimiStore,
        onOpenDrawer: @escaping () -> Void,
        onSwitchToHome: @escaping () -> Void,
        onOpenAssets: @escaping () -> Void
    ) {
        self.store = store
        self.onOpenDrawer = onOpenDrawer
        self.onSwitchToHome = onSwitchToHome
        self.onOpenAssets = onOpenAssets
    }

    private var periodTransactions: [TransactionItem] {
        let cal = MimiCalendar.gregorian
        let targetLedgerId = selectedLedgerFilterId ?? store.currentLedgerId

        return store.transactions.filter { tx in
            if selectedLedgerFilterId != "all" && tx.ledgerId != targetLedgerId {
                return false
            }
            guard tx.includeInStats else { return false }

            if selectedFilterType == "仅支出" && tx.type != .expense { return false }
            if selectedFilterType == "仅收入" && tx.type != .income { return false }

            switch selectedPeriod {
            case "周":
                let now = Date()
                guard let baseDate = cal.date(byAdding: .day, value: statsWeekOffset * 7, to: now) else { return true }
                guard let weekStart = cal.date(byAdding: .day, value: -6, to: baseDate) else { return true }
                let startOfDay = cal.startOfDay(for: weekStart)
                let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: baseDate) ?? baseDate
                return tx.date >= startOfDay && tx.date <= endOfDay
            case "月":
                return statsBillingPeriod.contains(tx.date)
            case "年":
                let txYear = cal.component(.year, from: tx.date)
                return txYear == statsYear
            case "自定义":
                let minDate = min(customStartDate, customEndDate)
                let maxDate = max(customStartDate, customEndDate)
                let startOfDay = cal.startOfDay(for: minDate)
                let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: maxDate) ?? maxDate
                return tx.date >= startOfDay && tx.date <= endOfDay
            default:
                return true
            }
        }
    }

    private var statsBillingPeriod: BillingPeriod {
        let cal = MimiCalendar.gregorian
        let base = store.currentBillingPeriod()
        guard statsMonthOffset != 0,
              let shifted = cal.date(byAdding: .month, value: statsMonthOffset, to: base.start) else {
            return base
        }
        return BillingPeriodEngine.period(containing: shifted, startDay: store.monthStartDay)
    }

    private var periodLabelText: String {
        switch selectedPeriod {
        case "周":
            if statsWeekOffset == 0 {
                return "本周 (最近 7 天)"
            } else if statsWeekOffset < 0 {
                return String(format: "往前第 %d 周", abs(statsWeekOffset))
            } else {
                return String(format: "往后第 %d 周", statsWeekOffset)
            }
        case "月":
            return statsBillingPeriod.displayRangeLabel
        case "年":
            return String(format: "%d年 全年", statsYear)
        case "自定义":
            let f = DateFormatter()
            f.dateFormat = "yyyy/MM/dd"
            return "\(f.string(from: customStartDate)) ~ \(f.string(from: customEndDate))"
        default:
            return "全部历史账单"
        }
    }

    private func navigatePeriod(forward: Bool) {
        let cal = Calendar(identifier: .gregorian)
        let delta = forward ? 1 : -1
        switch selectedPeriod {
        case "月":
            statsMonthOffset += delta
        case "周":
            statsWeekOffset += delta
        case "年":
            statsYear += delta
        case "自定义":
            let span = max(1, cal.dateComponents([.day], from: customStartDate, to: customEndDate).day ?? 1)
            if let newStart = cal.date(byAdding: .day, value: delta * span, to: customStartDate),
               let newEnd = cal.date(byAdding: .day, value: delta * span, to: customEndDate) {
                customStartDate = newStart
                customEndDate = newEnd
            }
        default:
            break
        }
    }

    private var balanceCardTitle: String {
        switch selectedPeriod {
        case "周": return "本周结余"
        case "月": return "本月结余"
        case "年": return "年度结余"
        default: return "累计结余"
        }
    }

    private var totalExpense: Double {
        periodTransactions.filter { $0.type == .expense }.reduce(0.0) { $0 + $1.amount }
    }

    private var totalIncome: Double {
        periodTransactions.filter { $0.type == .income }.reduce(0.0) { $0 + $1.amount }
    }

    private var netBalance: Double {
        totalIncome - totalExpense
    }

    private var categoryBreakdown: [(name: String, icon: String, amount: Double, percent: Double, count: Int, color: Color)] {
        let source = periodTransactions.filter { $0.type == selectedChartType }
        let total = max(1.0, source.reduce(0.0) { $0 + $1.amount })
        var grouped: [String: (icon: String, sum: Double, count: Int)] = [:]
        for tx in source {
            let primary = tx.categoryPath.components(separatedBy: "-").first ?? tx.categoryPath
            let prev = grouped[primary] ?? (icon: tx.iconName, sum: 0, count: 0)
            grouped[primary] = (icon: prev.icon.isEmpty ? tx.iconName : prev.icon, sum: prev.sum + tx.amount, count: prev.count + 1)
        }
        let palette: [Color] = [
            MimiTheme.expenseBlue,
            MimiTheme.chartBlue,
            MimiTheme.heatmapExpense3,
            MimiTheme.heatmapExpense2,
            MimiTheme.incomeOrange,
            MimiTheme.balanceGreen,
            MimiTheme.chartPurple
        ]
        return grouped
            .map { (key, val) in (name: key, icon: val.icon, amount: val.sum, percent: val.sum / total, count: val.count) }
            .sorted { $0.amount > $1.amount }
            .enumerated()
            .map { idx, item in
                (
                    name: item.name,
                    icon: item.icon,
                    amount: item.amount,
                    percent: item.percent,
                    count: item.count,
                    color: palette[idx % palette.count]
                )
            }
    }

    private var chartCenterTotal: Double {
        selectedChartType == .expense ? totalExpense : totalIncome
    }

    private var chartCenterLabel: String {
        switch selectedPeriod {
        case "周": return selectedChartType == .expense ? "本周支出" : "本周收入"
        case "年": return selectedChartType == .expense ? "本年支出" : "本年收入"
        default: return selectedChartType == .expense ? "本月支出" : "本月收入"
        }
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    topBar
                    periodSegmentedControl
                    capybaraBalanceCard
                    donutBreakdownCard
                    dailyTrendBarCard
                    top10SingleExpenseCard
                    tabularBillSummaryCard
                }
                .padding(16)
                .padding(.bottom, 40)
            }
            .background(MimiTheme.background.ignoresSafeArea())
            .navigationDestination(isPresented: Binding(
                get: { drillCategoryName != nil },
                set: { if !$0 { drillCategoryName = nil } }
            )) {
                if let name = drillCategoryName {
                    let matchingBills = periodTransactions.filter { tx in
                        guard tx.type == selectedChartType else { return false }
                        let primary = tx.categoryPath.components(separatedBy: "-").first ?? tx.categoryPath
                        return primary == name
                    }
                    let periodStart = statsBillingPeriod.start
                    let y = MimiCalendar.gregorian.component(.year, from: periodStart)
                    let m = MimiCalendar.gregorian.component(.month, from: periodStart)
                    CategoryBillsListView(
                        store: store,
                        categoryName: name,
                        transactionType: selectedChartType,
                        year: y,
                        month: m,
                        scopedTransactions: matchingBills,
                        periodRangeLabel: periodLabelText,
                        onSelectTransaction: { tx in
                            billForDetail = tx
                        },
                        onDismiss: {
                            drillCategoryName = nil
                        }
                    )
                    .navigationBarBackButtonHidden(true)
                    .mimiInteractivePopGestureEnabled()
                }
            }
            .sheet(item: $billForDetail) { tx in
                BillDetailSheetView(store: store, transaction: tx) {
                    billForDetail = nil
                }
                .mimiInteractiveSheet()
            }
        }
        .mimiEdgeSwipeBack(isEnabled: drillCategoryName == nil) {
            onSwitchToHome()
        }
    }

    // MARK: - Top Navigation Bar (< 记录 | 统计 ⌄ | 全部账本 ⌄ | 筛选)

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: onSwitchToHome) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .mimiFont(15, weight: .bold)
                    Text("记录", bundle: .mimiModule)
                        .mimiFont(14, weight: .semibold)
                }
                .foregroundColor(MimiTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(MimiTheme.cardBackground))
            }
            .mimiPressable()

            Menu {
                Button(MimiL10n.string("记录 (首页)")) { onSwitchToHome() }
                Button(MimiL10n.string("Mimi (图表统计)")) {
                    // Already on stats — keep menu dismiss-only.
                }
                .disabled(true)
                Button(MimiL10n.string("资产管理")) { onOpenAssets() }
            } label: {
                HStack(spacing: 4) {
                    Text("统计", bundle: .mimiModule)
                        .mimiFont(20, weight: .bold, design: .rounded)
                        .foregroundColor(MimiTheme.textPrimary)
                    Image(systemName: "chevron.down")
                        .mimiFont(11, weight: .bold)
                        .foregroundColor(MimiTheme.textSecondary)
                }
            }

            Spacer()

            Menu {
                Button("当前账本 (\(store.currentLedgerName))") { selectedLedgerFilterId = store.currentLedgerId }
                Button(MimiL10n.string("全部账本合并")) { selectedLedgerFilterId = "all" }
                Divider()
                ForEach(store.ledgers) { l in
                    Button(l.name) { selectedLedgerFilterId = l.id }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedLedgerFilterId == "all" ? "全部账本" : (store.ledgers.first(where: { $0.id == selectedLedgerFilterId })?.name ?? store.currentLedgerName))
                        .mimiFont(11, weight: .semibold)
                        .foregroundColor(MimiTheme.textPrimary)
                    Image(systemName: "chevron.down")
                        .mimiFont(9, weight: .bold)
                        .foregroundColor(MimiTheme.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(MimiTheme.cardBackground))
            }

            Menu {
                Button(MimiL10n.string("全部类型")) { selectedFilterType = "全部" }
                Button(MimiL10n.string("仅看支出")) { selectedFilterType = "仅支出" }
                Button(MimiL10n.string("仅看收入")) { selectedFilterType = "仅收入" }
            } label: {
                HStack(spacing: 3) {
                    Text(selectedFilterType == "全部" ? "筛选" : selectedFilterType)
                        .mimiFont(11, weight: .semibold)
                        .foregroundColor(MimiTheme.textPrimary)
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .mimiFont(11)
                        .foregroundColor(MimiTheme.expenseBlue)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(MimiTheme.cardBackground))
            }
        }
    }

    // MARK: - Period Control (周 | 月 | 年 | 自定义 + 前进后退导航)

    private var periodSegmentedControl: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(["周", "月", "年", "自定义"], id: \.self) { period in
                    Button {
                        selectedPeriod = period
                    } label: {
                        Text(period)
                            .mimiFont(13, weight: selectedPeriod == period ? .bold : .medium)
                            .foregroundColor(selectedPeriod == period ? MimiTheme.textPrimary : MimiTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedPeriod == period ? Color.white : Color.clear)
                            )
                    }
                    .mimiPressable()
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 12).fill(MimiTheme.progressTrack))

            // Period navigator: < 2026年11月 >
            HStack {
                Button { navigatePeriod(forward: false) } label: {
                    Image(systemName: "chevron.left")
                        .mimiFont(13, weight: .bold)
                        .foregroundColor(MimiTheme.textSecondary)
                        .mimiMinTouchTarget()
                }
                .mimiPressable()
                .accessibilityLabel(MimiL10n.string("上一段时间"))

                Spacer()

                Text(periodLabelText)
                    .mimiFont(15, weight: .bold, design: .rounded)
                    .foregroundColor(MimiTheme.textPrimary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)

                Spacer()

                Button { navigatePeriod(forward: true) } label: {
                    Image(systemName: "chevron.right")
                        .mimiFont(13, weight: .bold)
                        .foregroundColor(MimiTheme.textSecondary)
                        .mimiMinTouchTarget()
                }
                .mimiPressable()
                .accessibilityLabel(MimiL10n.string("下一段时间"))
            }

            if selectedPeriod == "自定义" {
                HStack(spacing: 8) {
                    MimiDateFieldButton(
                        label: "起",
                        date: $customStartDate,
                        mode: .date,
                        title: "日期"
                    )
                    MimiDateFieldButton(
                        label: "止",
                        date: $customEndDate,
                        mode: .date,
                        title: "日期"
                    )
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(MimiTheme.cardBackground))
            }
        }
    }

    // MARK: - Balance Overview Banner (总支出, 总收入, 净结余 一样大三等分展示)

    private var capybaraBalanceCard: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("支出", bundle: .mimiModule)
                    .mimiFont(12, weight: .medium)
                    .foregroundColor(MimiTheme.textSecondary)
                Text(MimiTheme.formatRM(totalExpense))
                    .mimiFont(17, weight: .bold, design: .rounded)
                    .foregroundColor(MimiTheme.expenseBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 36)

            VStack(spacing: 6) {
                Text("收入", bundle: .mimiModule)
                    .mimiFont(12, weight: .medium)
                    .foregroundColor(MimiTheme.textSecondary)
                Text(MimiTheme.formatRM(totalIncome))
                    .mimiFont(17, weight: .bold, design: .rounded)
                    .foregroundColor(MimiTheme.incomeOrange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 36)

            VStack(spacing: 6) {
                Text("结余", bundle: .mimiModule)
                    .mimiFont(12, weight: .medium)
                    .foregroundColor(MimiTheme.textSecondary)
                Text(netBalance >= 0 ? MimiTheme.formatRM(netBalance) : "-\(MimiTheme.formatRM(abs(netBalance)))")
                    .mimiFont(17, weight: .bold, design: .rounded)
                    .foregroundColor(MimiTheme.balanceGreen)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 20).fill(MimiTheme.cardBackground))
    }

    // MARK: - Donut Chart: 支出分类构成 (IMG_2254)

    private var donutBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(selectedChartType == .expense ? "支出分类构成" : "收入分类构成")
                    .mimiFont(15, weight: .bold)
                    .foregroundColor(MimiTheme.textPrimary)
                Spacer()
                HStack(spacing: 0) {
                    Button { selectedChartType = .expense } label: {
                        Text("支出", bundle: .mimiModule)
                            .mimiFont(12, weight: selectedChartType == .expense ? .bold : .medium)
                            .foregroundColor(selectedChartType == .expense ? MimiTheme.expenseBlue : MimiTheme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(selectedChartType == .expense ? Color.white : Color.clear))
                    }
                    .mimiPressable()
                    Button { selectedChartType = .income } label: {
                        Text("收入", bundle: .mimiModule)
                            .mimiFont(12, weight: selectedChartType == .income ? .bold : .medium)
                            .foregroundColor(selectedChartType == .income ? MimiTheme.expenseBlue : MimiTheme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(selectedChartType == .income ? Color.white : Color.clear))
                    }
                    .mimiPressable()
                }
                .padding(3)
                .background(Capsule().fill(MimiTheme.fillSubtle))
            }

            HStack {
                Spacer()
                let slices = categoryBreakdown
                ZStack {
                    Circle()
                        .stroke(MimiTheme.fillSubtle, lineWidth: 22)
                        .frame(width: 150, height: 150)

                    ForEach(Array(donutTrimRanges(for: slices).enumerated()), id: \.offset) { idx, range in
                        Circle()
                            .trim(from: range.from, to: range.to)
                            .stroke(
                                slices[idx].color,
                                style: StrokeStyle(lineWidth: 22, lineCap: .butt)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 150, height: 150)
                    }

                    VStack(spacing: 4) {
                        Text(chartCenterLabel)
                            .mimiFont(11)
                            .foregroundColor(MimiTheme.textMuted)
                        Text(MimiTheme.formatRM(chartCenterTotal))
                            .mimiFont(15, weight: .bold, design: .rounded)
                            .foregroundColor(MimiTheme.textPrimary)
                    }
                }
                Spacer()
            }

            if categoryBreakdown.isEmpty {
                Text(selectedChartType == .expense ? "暂无支出分类数据" : "暂无收入分类数据")
                    .mimiFont(13)
                    .foregroundColor(MimiTheme.textMuted)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(categoryBreakdown.enumerated()), id: \.offset) { _, row in
                        Button {
                            drillCategoryName = row.name
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    MimiStickerIconView(
                                        iconName: row.icon,
                                        categoryName: row.name,
                                        transactionType: selectedChartType,
                                        size: 32
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(row.name)
                                                .mimiFont(14, weight: .semibold)
                                                .foregroundColor(MimiTheme.textPrimary)
                                            Text(String(format: "%.2f%%", row.percent * 100))
                                                .mimiFont(12, design: .rounded)
                                                .foregroundColor(MimiTheme.textMuted)
                                        }
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                Capsule().fill(MimiTheme.fillSubtle).frame(height: 6)
                                                Capsule()
                                                    .fill(row.color.opacity(0.85))
                                                    .frame(width: max(4, geo.size.width * CGFloat(row.percent)), height: 6)
                                            }
                                        }
                                        .frame(height: 6)
                                    }
                                    Spacer(minLength: 8)
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(MimiTheme.formatRM(row.amount))
                                            .mimiFont(14, weight: .bold, design: .rounded)
                                            .foregroundColor(MimiTheme.textPrimary)
                                        Text("\(row.count)笔")
                                            .mimiFont(11)
                                            .foregroundColor(MimiTheme.textMuted)
                                    }
                                    Image(systemName: "chevron.right")
                                        .mimiFont(11, weight: .semibold)
                                        .foregroundColor(MimiTheme.textMuted)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .mimiPressable()
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(MimiTheme.cardBackground))
    }

    private func donutTrimRanges(
        for slices: [(name: String, icon: String, amount: Double, percent: Double, count: Int, color: Color)]
    ) -> [(from: CGFloat, to: CGFloat)] {
        var cursor: CGFloat = 0
        return slices.map { slice in
            let from = cursor
            let to = min(1, cursor + CGFloat(slice.percent))
            cursor = to
            return (from: from, to: to)
        }
    }

    // MARK: - Bar Chart: 每日支出趋势 (IMG_2255)

    private var dailyTrendBarCard: some View {
        let cal = Calendar(identifier: .gregorian)
        let labels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        let weekdayMap = [2, 3, 4, 5, 6, 7, 1]
        let bars: [(label: String, value: Double)] = zip(labels, weekdayMap).map { label, wd in
            let dayTx = periodTransactions.filter { cal.component(.weekday, from: $0.date) == wd }
            let exp = dayTx.filter { $0.type == .expense }.reduce(0.0) { $0 + $1.amount }
            let inc = dayTx.filter { $0.type == .income }.reduce(0.0) { $0 + $1.amount }
            let value: Double
            switch trendMode {
            case "收入": value = inc
            case "结余": value = inc - exp
            default: value = exp
            }
            return (label: label, value: value)
        }
        let maxVal = max(1.0, bars.map { abs($0.value) }.max() ?? 1.0)
        let avgBase: Double = {
            switch trendMode {
            case "收入": return totalIncome / 7.0
            case "结余": return netBalance / 7.0
            default: return totalExpense / 7.0
            }
        }()
        let barColor: Color = {
            switch trendMode {
            case "收入": return MimiTheme.incomeOrange
            case "结余": return MimiTheme.balanceGreen
            default: return MimiTheme.expenseBlue
            }
        }()

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(trendMode == "支出" ? "每日支出趋势" : (trendMode == "收入" ? "每日收入趋势" : "每日结余趋势"))
                    .mimiFont(15, weight: .bold)
                    .foregroundColor(MimiTheme.textPrimary)
                Spacer()
                HStack(spacing: 0) {
                    ForEach(["支出", "收入", "结余"], id: \.self) { mode in
                        Button { trendMode = mode } label: {
                            Text(mode)
                                .mimiFont(11, weight: trendMode == mode ? .bold : .medium)
                                .foregroundColor(trendMode == mode ? MimiTheme.expenseBlue : MimiTheme.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(trendMode == mode ? Color.white : Color.clear))
                        }
                        .mimiPressable()
                    }
                }
                .padding(3)
                .background(Capsule().fill(MimiTheme.fillSubtle))
            }

            Text("日均 \(MimiTheme.formatRM(avgBase))")
                .mimiFont(11)
                .foregroundColor(MimiTheme.textMuted)

            HStack(alignment: .bottom, spacing: 12) {
                ForEach(bars, id: \.label) { bar in
                    VStack(spacing: 6) {
                        if abs(bar.value) > 0.009 {
                            Text(String(format: "%.0f", bar.value))
                                .mimiFont(9, weight: .semibold, design: .rounded)
                                .foregroundColor(barColor)
                        }
                        RoundedRectangle(cornerRadius: 6)
                            .fill(abs(bar.value) > 0.009 ? barColor : MimiTheme.fillSubtle)
                            .frame(height: max(8, CGFloat(abs(bar.value) / maxVal) * 110))
                        Text(bar.label)
                            .mimiFont(10)
                            .foregroundColor(MimiTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 145, alignment: .bottom)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(MimiTheme.cardBackground))
    }

    // MARK: - Top 10 List: 单笔支出排行 (IMG_2256)

    private var top10SingleExpenseCard: some View {
        let allRanked = periodTransactions
            .filter { rankingMode == "收入" ? $0.type == .income : $0.type == .expense }
            .sorted { $0.amount > $1.amount }
        let ranked = Array(allRanked.prefix(10))
        let visible = isRankingExpanded ? ranked : Array(ranked.prefix(5))

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(rankingMode == "收入" ? "单笔收入排行" : "单笔支出排行")
                    .mimiFont(15, weight: .bold)
                    .foregroundColor(MimiTheme.textPrimary)
                Spacer()
                HStack(spacing: 0) {
                    ForEach(["支出", "收入"], id: \.self) { mode in
                        Button { rankingMode = mode } label: {
                            Text(mode)
                                .mimiFont(11, weight: rankingMode == mode ? .bold : .medium)
                                .foregroundColor(rankingMode == mode ? MimiTheme.expenseBlue : MimiTheme.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(rankingMode == mode ? Color.white : Color.clear))
                        }
                        .mimiPressable()
                    }
                }
                .padding(3)
                .background(Capsule().fill(MimiTheme.fillSubtle))
            }

            if ranked.isEmpty {
                Text(rankingMode == "收入" ? "暂无单笔收入记录" : "暂无单笔支出记录")
                    .mimiFont(13)
                    .foregroundColor(MimiTheme.textMuted)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(visible.enumerated()), id: \.element.id) { idx, item in
                    Button {
                        billForDetail = item
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(idx + 1)")
                                .mimiFont(12, weight: .bold, design: .rounded)
                                .foregroundColor(idx < 3 ? MimiTheme.expenseBlue : MimiTheme.textMuted)
                                .frame(width: 18)

                            MimiStickerIconView(
                                iconName: item.iconName,
                                categoryName: item.categoryPath,
                                transactionType: item.type,
                                size: 32
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.categoryPath)
                                    .mimiFont(13, weight: .semibold)
                                    .foregroundColor(MimiTheme.textPrimary)
                                if !item.note.isEmpty {
                                    Text(item.note)
                                        .mimiFont(11)
                                        .foregroundColor(MimiTheme.textMuted)
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 8)

                            Text(MimiTheme.formatRM(item.amount))
                                .mimiFont(14, weight: .bold, design: .rounded)
                                .foregroundColor(rankingMode == "收入" ? MimiTheme.incomeOrange : MimiTheme.expenseBlue)

                            Image(systemName: "chevron.right")
                                .mimiFont(11, weight: .semibold)
                                .foregroundColor(MimiTheme.textMuted)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(idx < 3 ? MimiTheme.rowHoverSoft : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .mimiPressable()
                    .accessibilityLabel("打开账单 \(item.categoryPath)")
                }

                if ranked.count > 5 {
                    Button {
                        withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                            isRankingExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isRankingExpanded ? "chevron.up" : "chevron.down")
                                .mimiFont(11, weight: .semibold)
                            Text(isRankingExpanded ? "收起" : "展开全部")
                                .mimiFont(12, weight: .medium)
                        }
                        .foregroundColor(MimiTheme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }
                    .mimiPressable()
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(MimiTheme.cardBackground))
    }

    // MARK: - Tabular Summary: 账单汇总 (IMG_2257)

    private var tabularBillSummaryCard: some View {
        let cal = Calendar(identifier: .gregorian)
        let dayRows: [(label: String, exp: Double, inc: Double, net: Double)] = {
            var map: [Date: (exp: Double, inc: Double)] = [:]
            let labelFmt = DateFormatter()
            labelFmt.dateFormat = "M.d"
            for tx in periodTransactions {
                let day = cal.startOfDay(for: tx.date)
                var cur = map[day] ?? (0, 0)
                if tx.type == .expense { cur.exp += tx.amount }
                if tx.type == .income { cur.inc += tx.amount }
                map[day] = cur
            }
            return map.keys.sorted(by: >).map { day in
                let v = map[day]!
                return (label: labelFmt.string(from: day), exp: v.exp, inc: v.inc, net: v.inc - v.exp)
            }
        }()
        let dayCount = max(1, dayRows.count)
        let avgExp = totalExpense / Double(dayCount)
        let avgInc = totalIncome / Double(dayCount)
        let avgNet = netBalance / Double(dayCount)

        return VStack(alignment: .leading, spacing: 12) {
            Text("账单汇总", bundle: .mimiModule)
                .mimiFont(15, weight: .bold)
                .foregroundColor(MimiTheme.textPrimary)

            VStack(spacing: 0) {
                HStack {
                    Text("日期", bundle: .mimiModule).frame(maxWidth: .infinity, alignment: .leading)
                    Text("支出", bundle: .mimiModule).frame(maxWidth: .infinity).foregroundColor(MimiTheme.expenseBlue)
                    Text("收入", bundle: .mimiModule).frame(maxWidth: .infinity).foregroundColor(MimiTheme.incomeOrange)
                    Text("结余", bundle: .mimiModule).frame(maxWidth: .infinity).foregroundColor(MimiTheme.balanceGreen)
                }
                .mimiFont(11, weight: .bold)
                .padding(10)
                .background(MimiTheme.surfaceMuted)

                summaryTableRow(label: "总计", exp: totalExpense, inc: totalIncome, net: netBalance, emphasize: true)
                summaryTableRow(label: "日均", exp: avgExp, inc: avgInc, net: avgNet, emphasize: true)

                if dayRows.isEmpty {
                    Text("暂无账单", bundle: .mimiModule)
                        .mimiFont(12)
                        .foregroundColor(MimiTheme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                } else {
                    ForEach(Array(dayRows.enumerated()), id: \.offset) { idx, row in
                        summaryTableRow(label: row.label, exp: row.exp, inc: row.inc, net: row.net, emphasize: false)
                            .background(idx % 2 == 0 ? Color.white : MimiTheme.fillSubtle)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(MimiTheme.divider, lineWidth: 1))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(MimiTheme.cardBackground))
    }

    private func summaryTableRow(label: String, exp: Double, inc: Double, net: Double, emphasize: Bool) -> some View {
        HStack {
            Text(label)
                .mimiFont(12, weight: emphasize ? .bold : .regular, design: .rounded)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(MimiTheme.formatRM(exp))
                .mimiFont(12, weight: emphasize ? .semibold : .regular, design: .rounded)
                .foregroundColor(MimiTheme.expenseBlue)
                .frame(maxWidth: .infinity)
            Text(MimiTheme.formatRM(inc))
                .mimiFont(12, weight: emphasize ? .semibold : .regular, design: .rounded)
                .foregroundColor(MimiTheme.incomeOrange)
                .frame(maxWidth: .infinity)
            Text(net >= 0 ? MimiTheme.formatRM(net) : "-\(MimiTheme.formatRM(abs(net)))")
                .mimiFont(12, weight: emphasize ? .semibold : .regular, design: .rounded)
                .foregroundColor(MimiTheme.balanceGreen)
                .frame(maxWidth: .infinity)
        }
        .padding(10)
    }
}
