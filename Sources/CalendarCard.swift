import SwiftUI

/// "日历" tab: a Liquid Glass month card with lunar days, solar terms and important dates, plus details for
/// the chosen day.
struct CalendarCard: View {
    @ObservedObject var settings: ClockSettings
    @ObservedObject var store = ImportantDateStore.shared
    let namespace: Namespace.ID

    @State private var monthOffset = 0
    @State private var selected: DateComponents?

    private let weekdayHeaders = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        TimelineView(.everyMinute) { context in
            let calendar = Self.calendar(in: settings.effectiveTimeZone)
            let today = calendar.dateComponents([.year, .month, .day], from: context.date)
            let month = displayedMonth(today: today, calendar: calendar)
            let chosen = selected ?? today
            let marks = importantDates(in: month, calendar: calendar)

            VStack(spacing: 10) {
                monthHeader(month: month)
                grid(month: month, today: today, chosen: chosen, calendar: calendar, marks: marks)
                Divider()
                details(for: chosen, today: today, calendar: calendar)
            }
            .card(id: "calendar", in: namespace)
        }
    }

    // MARK: Header

    private func monthHeader(month: (year: Int, month: Int)) -> some View {
        let lunar = LunarCalendar.lunarDate(year: month.year, month: month.month, day: 15)
        return HStack(spacing: 8) {
            Text("\(String(month.year))年\(month.month)月")
                .font(.system(size: 15, weight: .bold))
                .contentTransition(.numericText())
            Text("\(lunar.yearName)\(lunar.zodiacName)年")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if monthOffset != 0 || selected != nil {
                Button("今天") {
                    withAnimation(Metrics.spring) {
                        monthOffset = 0
                        selected = nil
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .transition(.scale.combined(with: .opacity))
            }
            monthButton("chevron.left", step: -1, help: "上个月")
            monthButton("chevron.right", step: 1, help: "下个月")
        }
    }

    private func monthButton(_ symbol: String, step: Int, help: String) -> some View {
        Button {
            withAnimation(Metrics.spring) { monthOffset += step }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .help(help)
    }

    // MARK: Grid

    private func importantDates(in month: (year: Int, month: Int), calendar: Calendar) -> [DayStamp: [ImportantDateStore.Entry]] {
        let first = DayStamp(year: month.year, month: month.month, day: 1)
        let length = monthCells(year: month.year, month: month.month, calendar: calendar).compactMap { $0 }.count
        return store.entriesByDay(from: first, through: DayStamp(year: month.year, month: month.month, day: length))
    }

    private func grid(
        month: (year: Int, month: Int),
        today: DateComponents,
        chosen: DateComponents,
        calendar: Calendar,
        marks: [DayStamp: [ImportantDateStore.Entry]]
    ) -> some View {
        let cells = monthCells(year: month.year, month: month.month, calendar: calendar)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 3) {
            ForEach(weekdayHeaders, id: \.self) { header in
                Text(header)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(header == "六" || header == "日" ? Color.red.opacity(0.75) : Color.secondary)
                    .frame(height: 18)
            }
            ForEach(Array(cells.enumerated()), id: \.offset) { index, day in
                if let day {
                    dayCell(
                        year: month.year,
                        month: month.month,
                        day: day,
                        isWeekend: index % 7 >= 5,
                        isToday: today.year == month.year && today.month == month.month && today.day == day,
                        isSelected: chosen.year == month.year && chosen.month == month.month && chosen.day == day,
                        entries: marks[DayStamp(year: month.year, month: month.month, day: day)] ?? []
                    )
                } else {
                    Color.clear.frame(height: 38)
                }
            }
        }
    }

    private func dayCell(
        year: Int,
        month: Int,
        day: Int,
        isWeekend: Bool,
        isToday: Bool,
        isSelected: Bool,
        entries: [ImportantDateStore.Entry]
    ) -> some View {
        let term = SolarTerms.termName(year: year, month: month, day: day)
        let lunar = LunarCalendar.lunarDate(year: year, month: month, day: day)
        // Periods tint the whole run of days; single dates get a dot in their kind's color.
        let period = entries.first { $0.occurrence.start != $0.occurrence.end }
        let dots = entries.filter { $0.occurrence.start == $0.occurrence.end || $0.occurrence.start.day == day }
        return Button {
            withAnimation(Metrics.spring) { selected = DateComponents(year: year, month: month, day: day) }
        } label: {
            VStack(spacing: 0) {
                Text("\(day)")
                    .font(.system(size: 14, weight: isToday ? .bold : .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(isToday ? Color.white : (isWeekend ? Color.red.opacity(0.85) : Color.primary))
                Text(term ?? lunar.cellLabel)
                    .font(.system(size: 8.5, weight: term != nil || lunar.day == 1 ? .semibold : .regular))
                    .foregroundStyle(isToday ? Color.white.opacity(0.9) : (term != nil ? Color.accentColor : Color.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .overlay(alignment: .bottom) {
                HStack(spacing: 2) {
                    ForEach(dots.prefix(3)) { entry in
                        Circle()
                            .fill(isToday ? Color.white : entry.item.kind.tint)
                            .frame(width: 4, height: 4)
                    }
                }
                .offset(y: -1)
            }
            .background {
                if isToday {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.accentColor.gradient)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 4, y: 2)
                } else if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.accentColor.opacity(0.1)))
                } else if let period {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(period.item.kind.tint.opacity(0.16))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Details

    private func details(for day: DateComponents, today: DateComponents, calendar: Calendar) -> some View {
        let year = day.year ?? 2000
        let month = day.month ?? 1
        let dayOfMonth = day.day ?? 1
        let lunar = LunarCalendar.lunarDate(year: year, month: month, day: dayOfMonth)
        let date = calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 12)) ?? Date()
        let todayDate = calendar.date(from: DateComponents(year: today.year, month: today.month, day: today.day, hour: 12)) ?? Date()
        let distance = calendar.dateComponents([.day], from: todayDate, to: date).day ?? 0
        let term = SolarTerms.termName(year: year, month: month, day: dayOfMonth)
        let next = nextTerm(after: date)
        let stamp = DayStamp(year: year, month: month, day: dayOfMonth)
        let events = store.entriesByDay(from: stamp, through: stamp)[stamp] ?? []

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("\(month)月\(dayOfMonth)日 \(weekdayName(calendar.component(.weekday, from: date)))")
                    .font(.system(size: 13, weight: .semibold))
                if distance != 0 {
                    Text(distance > 0 ? "\(distance)天后" : "\(-distance)天前")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let term {
                    Text(term)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.gradient))
                }
            }
            Text("农历 \(lunar.fullName)")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            if let next {
                let days = calendar.dateComponents([.day], from: date, to: next.date).day ?? 0
                Label("下一节气：\(next.name) · \(termDateLabel(next.date))（\(days)天后）", systemImage: "leaf.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            ForEach(events) { entry in
                HStack(spacing: 5) {
                    Image(systemName: entry.item.kind.symbol)
                        .foregroundStyle(entry.item.kind.tint)
                    Text(entry.item.title)
                        .fontWeight(.semibold)
                    Text(entry.item.dateLabel(for: entry.occurrence))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11.5))
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Helpers

    static func calendar(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private func nextTerm(after date: Date) -> SolarTerms.Term? {
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        // Compare Beijing calendar days, so a term later on the selected day doesn't count as "next".
        let beijing = Self.calendar(in: LunarCalendar.beijing)
        let endOfDay = beijing.date(byAdding: .day, value: 1, to: beijing.startOfDay(for: date)) ?? date
        return (SolarTerms.terms(in: year) + SolarTerms.terms(in: year + 1)).first { $0.date >= endOfDay }
    }

    private func termDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = LunarCalendar.beijing
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private func weekdayName(_ weekday: Int) -> String {
        "星期" + ["日", "一", "二", "三", "四", "五", "六"][(weekday - 1) % 7]
    }

    private func displayedMonth(today: DateComponents, calendar: Calendar) -> (year: Int, month: Int) {
        let first = calendar.date(from: DateComponents(year: today.year, month: today.month, day: 1)) ?? Date()
        let shifted = calendar.date(byAdding: .month, value: monthOffset, to: first) ?? first
        let parts = calendar.dateComponents([.year, .month], from: shifted)
        return (parts.year ?? 2000, parts.month ?? 1)
    }

    /// Day numbers laid out Monday-first, padded with nils to whole weeks.
    private func monthCells(year: Int, month: Int, calendar: Calendar) -> [Int?] {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let leading = (calendar.component(.weekday, from: first) + 5) % 7
        var cells: [Int?] = Array(repeating: nil, count: leading) + range.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }
}
