import SwiftUI

/// Pure helpers for the calendar date/time sheet (unit-testable).
public enum MimiDatePickerLogic {
    public static let calendar = Calendar(identifier: .gregorian)
    public static let weekdayLabels = ["日", "一", "二", "三", "四", "五", "六"]

    public static func startOfMonth(_ date: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }

    public static func monthTitle(for date: Date) -> String {
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        return "\(y)年\(m)月"
    }

    public static func timeCapsuleText(for date: Date) -> String {
        String(
            format: "%02d:%02d",
            calendar.component(.hour, from: date),
            calendar.component(.minute, from: date)
        )
    }

    /// Merge calendar day from `day` with hour/minute from `timeSource`.
    public static func combining(day: Date, timeFrom timeSource: Date) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = calendar.component(.hour, from: timeSource)
        comps.minute = calendar.component(.minute, from: timeSource)
        comps.second = 0
        return calendar.date(from: comps) ?? day
    }

    /// Set hour/minute on `base` while keeping its calendar day.
    public static func setting(hour: Int, minute: Int, on base: Date) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: base)
        comps.hour = max(0, min(23, hour))
        comps.minute = max(0, min(59, minute))
        comps.second = 0
        return calendar.date(from: comps) ?? base
    }

    public static func shiftMonth(_ delta: Int, from visibleMonth: Date) -> Date {
        guard let next = calendar.date(byAdding: .month, value: delta, to: visibleMonth) else {
            return visibleMonth
        }
        return startOfMonth(next)
    }

    /// Days for a Sunday-first grid; leading/trailing `nil` pads.
    public static func daysInMonth(for visibleMonth: Date) -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth),
              let range = calendar.range(of: .day, in: .month, for: visibleMonth) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start) // 1=Sun
        let leading = firstWeekday - 1
        var days: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) {
                days.append(date)
            }
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }
}

/// 自家日历式日期/时间底栏：标题「日期」+「回今天」、月历选日、时间胶囊 + 滚轮、「确认」。
public struct MimiDatePickerSheet: View {
    public enum Mode {
        case date
        case dateAndTime
    }

    @Binding public var selection: Date
    public var title: String
    public var mode: Mode
    public var onDone: () -> Void

    @State private var draft: Date
    @State private var visibleMonth: Date
    @State private var showTimeWheel: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        selection: Binding<Date>,
        title: String = "日期",
        mode: Mode = .date,
        onDone: @escaping () -> Void
    ) {
        self._selection = selection
        self.title = title
        self.mode = mode
        self.onDone = onDone
        let initial = selection.wrappedValue
        self._draft = State(initialValue: initial)
        self._visibleMonth = State(initialValue: MimiDatePickerLogic.startOfMonth(initial))
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Capsule()
                    .fill(MimiTheme.strokeSubtle)
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                headerRow
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                monthHeader
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                weekdayHeader
                    .padding(.horizontal, 12)

                dayGrid
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                if mode == .dateAndTime {
                    timeRow
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                }

                confirmButton
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 20)
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(MimiTheme.cardBackground)
                    .ignoresSafeArea(edges: .bottom)
            )

            if showTimeWheel && mode == .dateAndTime {
                timeWheelOverlay
            }
        }
        .onAppear {
            draft = selection
            visibleMonth = MimiDatePickerLogic.startOfMonth(selection)
            showTimeWheel = false
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center) {
            Text(title)
                .mimiFont(17, weight: .bold)
                .foregroundColor(MimiTheme.textPrimary)
            Spacer(minLength: 8)
            Button {
                jumpToToday()
            } label: {
                Text("回今天", bundle: .mimiModule)
                    .mimiFont(14, weight: .semibold)
                    .foregroundColor(MimiTheme.expenseBlue)
                    .padding(.horizontal, 8)
                    .frame(minHeight: MimiHIG.minTouch)
                    .contentShape(Rectangle())
            }
            .mimiPressable()
            .accessibilityLabel(MimiL10n.string("回今天"))
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                visibleMonth = MimiDatePickerLogic.shiftMonth(-1, from: visibleMonth)
            } label: {
                Image(systemName: "chevron.left")
                    .mimiFont(14, weight: .bold)
                    .foregroundColor(MimiTheme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .mimiPressable()
            .accessibilityLabel(MimiL10n.string("上个月"))

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Text(MimiDatePickerLogic.monthTitle(for: visibleMonth))
                    .mimiFont(16, weight: .bold)
                    .foregroundColor(MimiTheme.textPrimary)
                Image(systemName: "chevron.right")
                    .mimiFont(11, weight: .bold)
                    .foregroundColor(MimiTheme.textMuted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(MimiDatePickerLogic.monthTitle(for: visibleMonth))

            Spacer(minLength: 4)

            Button {
                visibleMonth = MimiDatePickerLogic.shiftMonth(1, from: visibleMonth)
            } label: {
                Image(systemName: "chevron.right")
                    .mimiFont(14, weight: .bold)
                    .foregroundColor(MimiTheme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .mimiPressable()
            .accessibilityLabel(MimiL10n.string("下个月"))
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(MimiDatePickerLogic.weekdayLabels, id: \.self) { label in
                Text(label)
                    .mimiFont(12, weight: .semibold)
                    .foregroundColor(MimiTheme.textMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        let days = MimiDatePickerLogic.daysInMonth(for: visibleMonth)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
            spacing: 6
        ) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    let selected = MimiDatePickerLogic.calendar.isDate(day, inSameDayAs: draft)
                    let isToday = MimiDatePickerLogic.calendar.isDateInToday(day)
                    Button {
                        selectDay(day)
                    } label: {
                        Text("\(MimiDatePickerLogic.calendar.component(.day, from: day))")
                            .mimiFont(15, weight: selected ? .bold : .medium)
                            .foregroundColor(selected ? .white : MimiTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                Circle()
                                    .fill(selected ? MimiTheme.expenseBlue : Color.clear)
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        isToday && !selected
                                            ? MimiTheme.expenseBlue.opacity(0.45)
                                            : Color.clear,
                                        lineWidth: 1.2
                                    )
                            )
                            .contentShape(Circle())
                    }
                    .mimiPressable()
                    .accessibilityLabel(
                        "\(MimiDatePickerLogic.calendar.component(.day, from: day))日"
                    )
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    private var timeRow: some View {
        HStack(spacing: 12) {
            Text("时间", bundle: .mimiModule)
                .mimiFont(15, weight: .semibold)
                .foregroundColor(MimiTheme.textPrimary)

            Spacer()

            Button {
                withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                    showTimeWheel = true
                }
            } label: {
                Text(MimiDatePickerLogic.timeCapsuleText(for: draft))
                    .mimiFont(15, weight: .semibold, design: .rounded)
                    .foregroundColor(MimiTheme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(MimiTheme.fillSubtle)
                    )
                    .frame(minHeight: MimiHIG.minTouch)
                    .contentShape(Capsule())
            }
            .mimiPressable()
            .accessibilityLabel("\(MimiL10n.string("时间")) \(MimiDatePickerLogic.timeCapsuleText(for: draft))")
            .accessibilityHint(MimiL10n.string("点按调整时分"))
        }
    }

    private var confirmButton: some View {
        Button {
            selection = draft
            onDone()
        } label: {
            Text("确认", bundle: .mimiModule)
                .mimiFont(17, weight: .bold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(MimiTheme.expenseBlue)
                )
        }
        .buttonStyle(.plain)
        .mimiPressable()
        .accessibilityLabel(MimiL10n.string("确认"))
    }

    private var timeWheelOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                        showTimeWheel = false
                    }
                }
                .accessibilityLabel(MimiL10n.string("关闭时间选择"))

            VStack(spacing: 0) {
                HStack {
                    Text("时间", bundle: .mimiModule)
                        .mimiFont(16, weight: .bold)
                        .foregroundColor(MimiTheme.textPrimary)
                    Spacer()
                    Button {
                        withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                            showTimeWheel = false
                        }
                    } label: {
                        Text("确认", bundle: .mimiModule)
                            .mimiFont(15, weight: .semibold)
                            .foregroundColor(MimiTheme.expenseBlue)
                            .padding(.horizontal, 8)
                            .frame(minHeight: MimiHIG.minTouch)
                            .contentShape(Rectangle())
                    }
                    .mimiPressable()
                    .accessibilityLabel(MimiL10n.string("确认时间"))
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 4)

                DatePicker(
                    "",
                    selection: $draft,
                    displayedComponents: [.hourAndMinute]
                )
                #if os(iOS)
                .datePickerStyle(.wheel)
                #endif
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(MimiTheme.cardBackground)
            )
            .padding(.horizontal, 24)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    private func jumpToToday() {
        let now = Date()
        if mode == .dateAndTime {
            // Gold「回今天」jumps to the current instant (day + clock).
            draft = now
        } else {
            draft = MimiDatePickerLogic.setting(hour: 12, minute: 0, on: now)
        }
        visibleMonth = MimiDatePickerLogic.startOfMonth(draft)
    }

    private func selectDay(_ day: Date) {
        if mode == .dateAndTime {
            draft = MimiDatePickerLogic.combining(day: day, timeFrom: draft)
        } else {
            draft = MimiDatePickerLogic.setting(hour: 12, minute: 0, on: day)
        }
        visibleMonth = MimiDatePickerLogic.startOfMonth(day)
    }
}

/// 触发自家日期弹窗的按钮行（替代行内系统 DatePicker）。
public struct MimiDateFieldButton: View {
    public var label: String?
    @Binding public var date: Date
    public var mode: MimiDatePickerSheet.Mode
    public var title: String
    @State private var showSheet = false

    public init(
        label: String? = nil,
        date: Binding<Date>,
        mode: MimiDatePickerSheet.Mode = .date,
        title: String = "日期"
    ) {
        self.label = label
        self._date = date
        self.mode = mode
        self.title = title
    }

    public var body: some View {
        Button {
            showSheet = true
        } label: {
            HStack(spacing: 6) {
                if let label, !label.isEmpty {
                    Text(label)
                        .mimiFont(13, weight: .medium)
                        .foregroundColor(MimiTheme.textSecondary)
                }
                Text(displayText)
                    .mimiFont(14, weight: .semibold)
                    .foregroundColor(MimiTheme.textPrimary)
                Image(systemName: "chevron.down")
                    .mimiFont(11, weight: .bold)
                    .foregroundColor(MimiTheme.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: MimiHIG.minTouch)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MimiTheme.fillSubtle)
            )
            .contentShape(Rectangle())
        }
        .mimiPressable()
        .accessibilityLabel(accessibilityTitle)
        .sheet(isPresented: $showSheet) {
            MimiDatePickerSheet(
                selection: $date,
                title: title,
                mode: mode,
                onDone: { showSheet = false }
            )
            #if os(iOS)
            .mimiInteractiveSheet(
                detents: [.height(mode == .dateAndTime ? 560 : 500)],
                showDragIndicator: false
            )
            .presentationCornerRadius(24)
            #endif
        }
    }

    private var displayText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = mode == .dateAndTime ? "M月d日 HH:mm" : "M月d日"
        return f.string(from: date)
    }

    private var accessibilityTitle: String {
        if let label, !label.isEmpty {
            return "\(label) \(displayText)"
        }
        return displayText
    }
}
