import SwiftUI

public enum DrawerDestination: String, Identifiable, Sendable {
    case calendar = "全部记录"
    case stats = "图表统计"
    case assets = "资产管理"
    case ledgers = "账本管理"
    case budgets = "预算管理"
    case widgets = "小组件"
    case categories = "分类管理"
    case tags = "标签管理"
    case importExport = "导入导出"
    case autoBookkeeping = "自动记账"
    case scheduledBookkeeping = "定时记账"
    case settings = "设置"

    public var id: String { rawValue }
}

public struct SideDrawerMenuView: View {
    @ObservedObject public var store: MimiStore
    public var onClose: () -> Void
    public var onSelectDestination: (DrawerDestination) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var panelVisible: Bool = false

    public init(
        store: MimiStore,
        onClose: @escaping () -> Void,
        onSelectDestination: @escaping (DrawerDestination) -> Void
    ) {
        self.store = store
        self.onClose = onClose
        self.onSelectDestination = onSelectDestination
    }

    private var heatmapYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var heatmapMonth: Int {
        Calendar.current.component(.month, from: Date())
    }

    private var monthDayCells: [CalendarDaySummary] {
        DynamicBudgetEngine.buildMonthDayCells(
            year: heatmapYear,
            month: heatmapMonth,
            transactions: store.transactions
        )
    }

    private var heatmapMonthTitle: String {
        // Keep numeric layout; localize year/month particles via catalog templates when present.
        String(
            format: MimiL10n.string("%d年%d月"),
            heatmapYear,
            heatmapMonth
        )
    }

    private var heatmapLeadingBlanks: Int {
        let cal = Calendar(identifier: .gregorian)
        guard let first = cal.date(from: DateComponents(year: heatmapYear, month: heatmapMonth, day: 1)) else {
            return 0
        }
        // Week starts Monday: Sun=1 → 6 blanks, Mon=2 → 0 blanks
        let weekday = cal.component(.weekday, from: first)
        return (weekday + 5) % 7
    }

    private var threeColumnGrid: [GridItem] {
        [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ]
    }

    public var body: some View {
        GeometryReader { geo in
            let panelWidth = geo.size.width * MimiTheme.drawerWidthFraction
            ZStack(alignment: .leading) {
                MimiTheme.scrim
                    .opacity(panelVisible ? 1 : 0)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissDrawer()
                    }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: MimiTheme.drawerSectionSpacing) {
                        profileRow
                        heatmapCard
                        moreFeaturesCard
                        quickBookkeepingCard
                    }
                    .padding(MimiTheme.drawerContentPadding)
                    .padding(.top, MimiTheme.topChromeExtraPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .safeAreaPadding(.top)
                .frame(width: panelWidth, height: geo.size.height, alignment: .top)
                .background(MimiTheme.background.ignoresSafeArea())
                .offset(x: panelVisible ? 0 : -panelWidth)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(MimiMotion.drawer(reduceMotion: reduceMotion)) {
                panelVisible = true
            }
        }
    }

    private func dismissDrawer(then action: (() -> Void)? = nil) {
        withAnimation(MimiMotion.drawer(reduceMotion: reduceMotion)) {
            panelVisible = false
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MimiMotion.handoffDelay(.drawer, reduceMotion: reduceMotion)
        ) {
            if let action {
                action()
            } else {
                onClose()
            }
        }
    }

    private func openDestination(_ dest: DrawerDestination) {
        dismissDrawer {
            onSelectDestination(dest)
        }
    }

    // MARK: - Profile + 设置图标（去掉底部设置/问卷行）

    private var profileRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(MimiTheme.vipSoft)
                    .frame(width: MimiTheme.drawerAvatarSize, height: MimiTheme.drawerAvatarSize)
                Text(String(store.userNickname.prefix(1)).uppercased())
                    .mimiFont(20, weight: .bold, design: .rounded)
                    .foregroundColor(MimiTheme.vipText)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(store.userNickname)
                        .mimiFont(18, weight: .bold)
                        .foregroundColor(MimiTheme.textPrimary)
                    Text("Pro")
                        .mimiFont(10, weight: .bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(MimiTheme.proBadgeBlue))
                }
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill")
                        .mimiFont(10)
                        .foregroundColor(MimiTheme.vipGold)
                    Text("VIP")
                        .mimiFont(11, weight: .semibold)
                        .foregroundColor(MimiTheme.vipGold)
                }
            }

            Spacer()

            Button {
                openDestination(.settings)
            } label: {
                Image(systemName: "gearshape")
                    .mimiFont(18, weight: .medium)
                    .foregroundColor(MimiTheme.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(MimiTheme.fillSubtle)
                    )
                    .mimiMinTouchTarget()
            }
            .mimiPressable()
            .accessibilityLabel(MimiL10n.string("设置"))
        }
        .padding(.top, 12)
    }

    // MARK: - Heatmap card

    private var heatmapCard: some View {
        Button {
            openDestination(.calendar)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text(heatmapMonthTitle)
                    .mimiFont(14, weight: .bold, design: .rounded)
                    .foregroundColor(MimiTheme.textPrimary)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7),
                    spacing: 3
                ) {
                    ForEach(0..<heatmapLeadingBlanks, id: \.self) { _ in
                        Color.clear
                            .frame(height: MimiTheme.drawerHeatmapCellHeight)
                    }
                    ForEach(monthDayCells, id: \.id) { cell in
                        heatmapCell(cell)
                    }
                }
                .padding(.vertical, 4)

                Divider().opacity(0.6)

                HStack(spacing: 0) {
                    statColumn(value: "\(store.recordedDaysCount)", label: "记录天数")
                    Divider().frame(height: 24)
                    statColumn(value: "\(store.totalRecordsCount)", label: "总记录")
                    Divider().frame(height: 24)
                    statColumn(value: "\(store.streakDaysCount)", label: "连续天数")
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: MimiTheme.cardCornerRadius, style: .continuous).fill(MimiTheme.cardBackground)
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            )
        }
        .mimiPressable()
    }

    private func heatmapCell(_ cell: CalendarDaySummary) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(cell.isToday ? MimiTheme.heatmapExpense1 : heatmapMiniColor(for: cell))
                .frame(height: MimiTheme.drawerHeatmapCellHeight)

            if cell.isToday {
                Text("今", bundle: .mimiModule)
                    .mimiFont(9, weight: .bold, design: .rounded)
                    .foregroundColor(MimiTheme.expenseBlue)
            } else {
                Text("\(cell.day)")
                    .mimiFont(9, weight: .regular, design: .rounded)
                    .foregroundColor(
                        cell.expense > 0 || cell.income > 0
                            ? MimiTheme.textPrimary
                            : MimiTheme.textMuted
                    )
            }
        }
    }

    // MARK: - Feature grids

    private var moreFeaturesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("更多功能", bundle: .mimiModule)
                .mimiFont(13, weight: .semibold)
                .foregroundColor(MimiTheme.textSecondary)

            LazyVGrid(columns: threeColumnGrid, spacing: 16) {
                drawerGridButton(title: "图表统计", dest: .stats) {
                    Image(systemName: "chart.pie")
                }
                drawerGridButton(title: "资产管理", dest: .assets) {
                    Image(systemName: "wallet.pass")
                }
                drawerGridButton(title: "账本管理", dest: .ledgers) {
                    Image(systemName: "book.closed")
                }
                drawerGridButton(title: "预算管理", dest: .budgets) {
                    Image(systemName: "pencil.and.list.clipboard")
                }
                drawerGridButton(title: "小组件", dest: .widgets) {
                    Image(systemName: "square.grid.2x2")
                }
                drawerGridButton(title: "分类管理", dest: .categories) {
                    Image(systemName: "folder.badge.plus")
                }
                drawerGridButton(title: "标签管理", dest: .tags) {
                    Image(systemName: "bookmark")
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: MimiTheme.cardCornerRadius, style: .continuous).fill(MimiTheme.cardBackground)
        )
    }

    private var quickBookkeepingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷记账", bundle: .mimiModule)
                .mimiFont(13, weight: .semibold)
                .foregroundColor(MimiTheme.textSecondary)

            LazyVGrid(columns: threeColumnGrid, spacing: 16) {
                drawerGridButton(title: "自动记账", dest: .autoBookkeeping) {
                    drawerDocGlyph("A")
                }
                drawerGridButton(title: "定时记账", dest: .scheduledBookkeeping) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: "doc")
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .mimiFont(10, weight: .semibold)
                            .offset(x: 2, y: 2)
                    }
                }
                drawerGridButton(title: "导入导出", dest: .importExport) {
                    Image(systemName: "doc.badge.plus")
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: MimiTheme.cardCornerRadius, style: .continuous).fill(MimiTheme.cardBackground)
        )
    }

    // MARK: - Helpers

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .mimiFont(19, weight: .bold, design: .rounded)
                .foregroundColor(MimiTheme.textPrimary)
            Text(LocalizedStringKey(label), bundle: .mimiModule)
                .mimiFont(11)
                .foregroundColor(MimiTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func heatmapMiniColor(for cell: CalendarDaySummary) -> Color {
        if cell.income > 0 && cell.expense == 0 {
            if cell.income > 500 { return MimiTheme.heatmapIncome2 }
            return MimiTheme.heatmapIncome1
        }
        if cell.expense > 0 {
            if cell.expense > 200 { return MimiTheme.heatmapExpense3 }
            if cell.expense > 30 { return MimiTheme.heatmapExpense2 }
            return MimiTheme.heatmapExpense1
        }
        return MimiTheme.heatmapEmpty
    }

    private func drawerDocGlyph(_ letter: String) -> some View {
        ZStack {
            Image(systemName: "doc")
            Text(letter)
                .mimiFont(11, weight: .bold, design: .rounded)
                .offset(y: 2)
        }
    }

    private func drawerGridButton<Icon: View>(
        title: String,
        dest: DrawerDestination,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button {
            openDestination(dest)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: MimiTheme.drawerGridIconCorner, style: .continuous)
                        .fill(MimiTheme.fillSubtle)
                        .frame(width: MimiTheme.drawerGridIconSize, height: MimiTheme.drawerGridIconSize)
                    icon()
                        .mimiFont(21, weight: .light)
                        .foregroundColor(MimiTheme.textPrimary)
                }
                Text(LocalizedStringKey(title), bundle: .mimiModule)
                    .mimiFont(12, weight: .medium)
                    .foregroundColor(MimiTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .mimiPressable()
        .accessibilityLabel(MimiL10n.string(title))
    }

}
