import SwiftUI

extension WorkSchedule.State {
    var tint: Color {
        switch self {
        case .working: return .green
        case .lunch: return .orange
        case .offWork: return .blue
        case .weekend: return .teal
        case .night: return .indigo
        }
    }

    /// What happens when this state begins, seen from `previous`: "下班", "上班", "午休"…
    func transitionVerb(from previous: WorkSchedule.State) -> String {
        switch (previous, self) {
        case (.lunch, .working): return "午休结束"
        case (_, .working): return "上班"
        case (_, .lunch): return "午休"
        case (.working, .offWork): return "下班"
        case (.night, _): return "天亮"
        case (_, .offWork): return "下班"
        case (_, .weekend): return "休息"
        case (_, .night): return "进入深夜"
        }
    }
}

/// Compact "国内工作时间 · 2小时后下班" line for the panel header.
struct WorkStatusBadge: View {
    let schedule: WorkSchedule
    let date: Date

    var body: some View {
        let status = schedule.status(at: date)
        HStack(spacing: 4) {
            Image(systemName: status.state.symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(status.state.tint)
            Text("国内\(status.state.title)")
                .font(.system(size: 11, weight: .medium))
            if let next = status.nextChange {
                let nextState = schedule.state(at: next)
                Text("· \(WorkSchedule.durationLabel(from: date, to: next))后\(nextState.transitionVerb(from: status.state))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(status.state.tint.opacity(0.14)))
        .help("按\(TimeZoneSearch.entry(for: schedule.timeZoneIdentifier).title)时间：工作 \(WorkSchedule.timeLabel(minuteOfDay: schedule.workStart))–\(WorkSchedule.timeLabel(minuteOfDay: schedule.workEnd))，可在详细设置 › 作息中修改")
    }
}

/// "日历" tab: month grid with lunar dates and solar terms, plus today's details.
struct CalendarPanelSection: View {
    @ObservedObject var settings: ClockSettings
    @ObservedObject var ultra: UltraSettings

    @State private var monthOffset = 0
    @State private var selected: DateComponents?

    private let weekdayHeaders = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        TimelineView(.everyMinute) { context in
            let calendar = WorldClockMath.calendar(in: settings.effectiveTimeZone)
            let today = calendar.dateComponents([.year, .month, .day], from: context.date)
            VStack(spacing: 10) {
                calendarModule(today: today, calendar: calendar)
                if ultra.showsWorkStatus {
                    workModule(now: context.date)
                }
            }
        }
    }

    // MARK: Month grid

    private func calendarModule(today: DateComponents, calendar: Calendar) -> some View {
        let month = displayedMonth(today: today, calendar: calendar)
        let cells = monthCells(year: month.year, month: month.month, calendar: calendar)
        let chosen = selected ?? today
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("\(String(month.year))年\(month.month)月")
                    .font(.system(size: 13, weight: .semibold))
                Text(LunarCalendar.lunarDate(year: month.year, month: month.month, day: 15).yearName + LunarCalendar.lunarDate(year: month.year, month: month.month, day: 15).zodiacName + "年")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if monthOffset != 0 || selected != nil {
                    PillButton(title: "今天", symbol: nil) {
                        monthOffset = 0
                        selected = nil
                    }
                }
                arrowButton("chevron.left") { monthOffset -= 1 }
                arrowButton("chevron.right") { monthOffset += 1 }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(weekdayHeaders, id: \.self) { header in
                    Text(header)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(header == "六" || header == "日" ? Color.red.opacity(0.75) : Color.secondary)
                        .frame(height: 16)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { index, day in
                    if let day {
                        dayCell(
                            year: month.year,
                            month: month.month,
                            day: day,
                            isWeekend: index % 7 >= 5,
                            isToday: today.year == month.year && today.month == month.month && today.day == day,
                            isSelected: chosen.year == month.year && chosen.month == month.month && chosen.day == day
                        )
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }

            Divider()
            detailLine(for: chosen, today: today, calendar: calendar)
        }
        .padding(8)
        .moduleBackground()
    }

    private func dayCell(year: Int, month: Int, day: Int, isWeekend: Bool, isToday: Bool, isSelected: Bool) -> some View {
        let term = SolarTerms.termName(year: year, month: month, day: day)
        let lunar = LunarCalendar.lunarDate(year: year, month: month, day: day)
        let subtitle = term ?? lunar.cellLabel
        return Button {
            selected = DateComponents(year: year, month: month, day: day)
        } label: {
            VStack(spacing: 0) {
                Text("\(day)")
                    .font(.system(size: 13, weight: isToday ? .bold : .medium).monospacedDigit())
                    .foregroundStyle(isToday ? Color.white : (isWeekend ? Color.red.opacity(0.8) : Color.primary))
                Text(subtitle)
                    .font(.system(size: 8.5, weight: term != nil || lunar.day == 1 ? .semibold : .regular))
                    .foregroundStyle(isToday ? Color.white.opacity(0.9) : (term != nil ? Color.accentColor : Color.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isToday ? Color.accentColor : (isSelected ? Color.primary.opacity(0.1) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func detailLine(for day: DateComponents, today: DateComponents, calendar: Calendar) -> some View {
        let year = day.year ?? 2000
        let month = day.month ?? 1
        let dayOfMonth = day.day ?? 1
        let lunar = LunarCalendar.lunarDate(year: year, month: month, day: dayOfMonth)
        let date = calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 12)) ?? Date()
        let todayDate = calendar.date(from: DateComponents(year: today.year, month: today.month, day: today.day, hour: 12)) ?? Date()
        let distance = calendar.dateComponents([.day], from: todayDate, to: date).day ?? 0
        let weekday = weekdayName(calendar.component(.weekday, from: date))
        let term = SolarTerms.termName(year: year, month: month, day: dayOfMonth)
        let next = nextTerm(after: date)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("\(month)月\(dayOfMonth)日 \(weekday)")
                    .font(.system(size: 12, weight: .semibold))
                if distance != 0 {
                    Text(distance > 0 ? "\(distance)天后" : "\(-distance)天前")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let term {
                    Text(term)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            Text("农历 \(lunar.fullName)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let next {
                let days = calendar.dateComponents([.day], from: date, to: next.date).day ?? 0
                Text("下一节气：\(next.name) · \(termDateLabel(next.date))（\(days)天后）")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func nextTerm(after date: Date) -> SolarTerms.Term? {
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        // Compare Beijing calendar days, so a term later on the selected day doesn't count as "next".
        let beijing = WorldClockMath.calendar(in: LunarCalendar.beijing)
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

    private func arrowButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
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

    // MARK: Work status

    private func workModule(now: Date) -> some View {
        let schedule = ultra.workSchedule
        let status = schedule.status(at: now)
        let zoneTitle = TimeZoneSearch.entry(for: schedule.timeZoneIdentifier).title
        return HStack(spacing: 10) {
            ToggleCircle(symbol: status.state.symbolName, isOn: status.state == .working)
            VStack(alignment: .leading, spacing: 1) {
                Text("国内作息 · \(status.state.title)")
                    .font(.system(size: 12, weight: .semibold))
                Group {
                    if let next = status.nextChange {
                        Text("\(zoneTitle) \(format(now, zone: schedule.timeZone)) · \(WorkSchedule.durationLabel(from: now, to: next))后\(schedule.state(at: next).transitionVerb(from: status.state))")
                    } else {
                        Text("\(zoneTitle) \(format(now, zone: schedule.timeZone))")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text("\(WorkSchedule.timeLabel(minuteOfDay: schedule.workStart))–\(WorkSchedule.timeLabel(minuteOfDay: schedule.workEnd))")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .moduleBackground()
    }

    private func format(_ date: Date, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
