import Foundation

/// An alarm at a wall-clock time in a specific time zone, optionally repeating on weekdays.
struct Alarm: Codable, Identifiable, Equatable {
    var id: UUID
    var hour: Int
    var minute: Int
    var timeZoneIdentifier: String
    var label: String
    /// Gregorian weekdays, 1 = Sunday … 7 = Saturday. Empty means a one-shot alarm.
    var repeatDays: Set<Int>
    var isEnabled: Bool
    /// Play the announcement sound and speak the label, instead of the plain notification sound.
    var speaks: Bool

    init(
        id: UUID = UUID(),
        hour: Int,
        minute: Int,
        timeZoneIdentifier: String,
        label: String = "",
        repeatDays: Set<Int> = [],
        isEnabled: Bool = true,
        speaks: Bool = true
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.timeZoneIdentifier = timeZoneIdentifier
        self.label = label
        self.repeatDays = repeatDays
        self.isEnabled = isEnabled
        self.speaks = speaks
    }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .gmt }

    var timeLabel: String { String(format: "%02d:%02d", hour, minute) }

    var displayLabel: String { label.isEmpty ? "闹钟" : label }

    /// First moment strictly after `date` when this alarm rings, in its own zone. DST-safe:
    /// a wall-clock time skipped by a spring-forward transition rings at the next valid time.
    func nextFireDate(after date: Date) -> Date? {
        let calendar = WorldClockMath.calendar(in: timeZone)
        if repeatDays.isEmpty {
            return calendar.nextDate(
                after: date,
                matching: DateComponents(hour: hour, minute: minute, second: 0),
                matchingPolicy: .nextTime
            )
        }
        return repeatDays.compactMap { weekday in
            calendar.nextDate(
                after: date,
                matching: DateComponents(hour: hour, minute: minute, second: 0, weekday: weekday),
                matchingPolicy: .nextTime
            )
        }.min()
    }

    static let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    /// "仅一次", "每天", "工作日", "周末", "周一 三 五"
    var repeatLabel: String {
        switch repeatDays {
        case []: return "仅一次"
        case Set(1...7): return "每天"
        case [2, 3, 4, 5, 6]: return "工作日"
        case [1, 7]: return "周末"
        default:
            let ordered = [2, 3, 4, 5, 6, 7, 1].filter(repeatDays.contains)
            return "周" + ordered.map { Self.weekdaySymbols[$0 - 1] }.joined(separator: " ")
        }
    }
}
