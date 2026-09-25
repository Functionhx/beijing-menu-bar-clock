import Foundation

/// Typical daily rhythm in China, used to tell whether people there are working, at lunch, off or asleep.
/// All times are minutes after midnight in `timeZoneIdentifier` (Beijing by default).
struct WorkSchedule: Codable, Equatable {
    var timeZoneIdentifier = "Asia/Shanghai"
    var workStart = 9 * 60
    var lunchStart = 12 * 60
    var lunchEnd = 13 * 60 + 30
    var workEnd = 18 * 60
    var nightStart = 23 * 60
    var nightEnd = 7 * 60
    /// Gregorian weekdays, 1 = Sunday … 7 = Saturday.
    var workdays: Set<Int> = [2, 3, 4, 5, 6]

    enum State: Equatable {
        case working
        case lunch
        case offWork
        case weekend
        case night

        var title: String {
            switch self {
            case .working: return "工作时间"
            case .lunch: return "午休"
            case .offWork: return "下班"
            case .weekend: return "休息日"
            case .night: return "深夜"
            }
        }

        var symbolName: String {
            switch self {
            case .working: return "briefcase.fill"
            case .lunch: return "fork.knife"
            case .offWork: return "house.fill"
            case .weekend: return "cup.and.saucer.fill"
            case .night: return "moon.zzz.fill"
            }
        }
    }

    struct Status: Equatable {
        let state: State
        /// When the state next changes, if within the next day.
        let nextChange: Date?
    }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: "Asia/Shanghai")! }

    func state(at date: Date) -> State {
        let calendar = WorldClockMath.calendar(in: timeZone)
        let minute = WorldClockMath.minuteOfDay(of: date, in: timeZone)
        let weekday = calendar.component(.weekday, from: date)

        if Self.contains(minute, from: nightStart, to: nightEnd) { return .night }
        guard workdays.contains(weekday) else { return .weekend }
        if Self.contains(minute, from: lunchStart, to: lunchEnd) { return .lunch }
        if Self.contains(minute, from: workStart, to: workEnd) { return .working }
        return .offWork
    }

    /// Current state plus the next boundary where it changes. Only the configured boundaries
    /// (and midnight, for weekday changes) of the next three days are checked, so it is cheap.
    func status(at date: Date) -> Status {
        let current = state(at: date)
        let boundaries = Set([workStart, lunchStart, lunchEnd, workEnd, nightStart, nightEnd, 0])
        var candidates: [Date] = []
        for dayOffset in 0...2 {
            let day = date.addingTimeInterval(TimeInterval(dayOffset * 86_400))
            for minute in boundaries {
                let candidate = WorldClockMath.date(atMinuteOfDay: minute, sameDayAs: day, in: timeZone)
                if candidate > date { candidates.append(candidate) }
            }
        }
        let next = candidates.sorted().first { state(at: $0) != current }
        return Status(state: current, nextChange: next)
    }

    /// Whether `minute` lies in [start, end), wrapping past midnight when end < start.
    static func contains(_ minute: Int, from start: Int, to end: Int) -> Bool {
        if start == end { return false }
        if start < end { return minute >= start && minute < end }
        return minute >= start || minute < end
    }

    /// "2小时15分", "40分钟"
    static func durationLabel(from start: Date, to end: Date) -> String {
        let minutes = max(0, Int((end.timeIntervalSince(start) / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes)分钟" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)小时" : "\(hours)小时\(rest)分"
    }

    static func timeLabel(minuteOfDay: Int) -> String {
        String(format: "%02d:%02d", minuteOfDay / 60 % 24, minuteOfDay % 60)
    }
}

/// Quiet hours for the voice announcement, in the clock's own zone.
struct QuietHours: Codable, Equatable {
    var isEnabled = false
    var start = 22 * 60
    var end = 8 * 60

    func contains(_ date: Date, in zone: TimeZone) -> Bool {
        isEnabled && WorkSchedule.contains(WorldClockMath.minuteOfDay(of: date, in: zone), from: start, to: end)
    }

    var label: String {
        "\(WorkSchedule.timeLabel(minuteOfDay: start))–\(WorkSchedule.timeLabel(minuteOfDay: end))"
    }
}
