import Foundation

/// One extra city shown in the world clock list.
struct WorldClockCity: Codable, Identifiable, Equatable {
    var id: UUID
    var timeZoneIdentifier: String

    init(id: UUID = UUID(), timeZoneIdentifier: String) {
        self.id = id
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .gmt
    }
}

/// Pure time math for the world clock and the time converter. DST-aware: every value is computed
/// for a specific instant, never from a zone's "current" offset.
enum WorldClockMath {
    /// Calendar-day difference of `date` seen in `zone` versus in `reference` (−1 昨天, 0 今天, +1 明天).
    static func dayOffset(of date: Date, in zone: TimeZone, relativeTo reference: TimeZone) -> Int {
        dayNumber(of: date, in: zone) - dayNumber(of: date, in: reference)
    }

    /// Seconds `zone` is ahead of `reference` at `date` (negative when behind).
    static func offsetDifference(_ zone: TimeZone, relativeTo reference: TimeZone, at date: Date) -> Int {
        zone.secondsFromGMT(for: date) - reference.secondsFromGMT(for: date)
    }

    /// "+13小时", "−2小时30分", "相同".
    static func differenceLabel(seconds: Int) -> String {
        guard seconds != 0 else { return "相同" }
        let sign = seconds < 0 ? "−" : "+"
        let hours = abs(seconds) / 3600
        let minutes = abs(seconds) % 3600 / 60
        switch (hours, minutes) {
        case (0, _): return "\(sign)\(minutes)分"
        case (_, 0): return "\(sign)\(hours)小时"
        default: return "\(sign)\(hours)小时\(minutes)分"
        }
    }

    static func dayOffsetLabel(_ offset: Int) -> String {
        switch offset {
        case 0: return "今天"
        case 1: return "明天"
        case -1: return "昨天"
        case let days where days > 0: return "\(days)天后"
        default: return "\(-offset)天前"
        }
    }

    static func hour(of date: Date, in zone: TimeZone) -> Int {
        calendar(in: zone).component(.hour, from: date)
    }

    /// Simple day/night split used for the sun/moon symbol.
    static func isDaytime(hour: Int) -> Bool {
        (6..<18).contains(hour)
    }

    /// The instant at `minuteOfDay` on the calendar day that contains `reference` in `zone`.
    /// Uses the calendar so DST days (23 or 25 hours long) land on the right wall-clock time.
    static func date(atMinuteOfDay minuteOfDay: Int, sameDayAs reference: Date, in zone: TimeZone) -> Date {
        let calendar = calendar(in: zone)
        let start = calendar.startOfDay(for: reference)
        return calendar.date(
            bySettingHour: minuteOfDay / 60 % 24,
            minute: minuteOfDay % 60,
            second: 0,
            of: start
        ) ?? start.addingTimeInterval(TimeInterval(minuteOfDay * 60))
    }

    static func minuteOfDay(of date: Date, in zone: TimeZone) -> Int {
        let parts = calendar(in: zone).dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func calendar(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// Days since 1970-01-01 of the wall-clock date in `zone`.
    private static func dayNumber(of date: Date, in zone: TimeZone) -> Int {
        let parts = calendar(in: zone).dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let midnight = utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)) ?? date
        return Int((midnight.timeIntervalSince1970 / 86_400).rounded(.down))
    }
}
