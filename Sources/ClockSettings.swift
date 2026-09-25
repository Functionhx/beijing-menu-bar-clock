import Foundation

@MainActor
final class ClockSettings: ObservableObject {
    static let shared = ClockSettings()
    static let changed = Notification.Name("ClockSettingsChanged")

    private enum Key {
        static let showDate = "showDate"
        static let showWeekday = "showWeekday"
        static let flashSeparators = "flashSeparators"
        static let showSeconds = "showSeconds"
        static let timeZoneIdentifier = "timeZoneIdentifier"
        static let useSystemTimeZone = "useSystemTimeZone"
        static let recentTimeZoneIdentifiers = "recentTimeZoneIdentifiers"
    }

    let quickTimeZoneChoices = [
        "Asia/Shanghai", "Asia/Hong_Kong", "Asia/Taipei", "Asia/Tokyo", "Asia/Singapore",
        "Europe/London", "Europe/Paris", "America/New_York", "America/Los_Angeles"
    ]

    @Published var showDate: Bool { didSet { save(Key.showDate, showDate) } }
    @Published var showWeekday: Bool { didSet { save(Key.showWeekday, showWeekday) } }
    @Published var flashSeparators: Bool { didSet { save(Key.flashSeparators, flashSeparators) } }
    @Published var showSeconds: Bool { didSet { save(Key.showSeconds, showSeconds) } }
    @Published var timeZoneIdentifier: String { didSet { save(Key.timeZoneIdentifier, timeZoneIdentifier) } }
    @Published var useSystemTimeZone: Bool { didSet { save(Key.useSystemTimeZone, useSystemTimeZone) } }
    @Published private(set) var recentTimeZoneIdentifiers: [String] {
        didSet { defaults.set(recentTimeZoneIdentifiers, forKey: Key.recentTimeZoneIdentifiers) }
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.showDate: true,
            Key.showWeekday: true,
            Key.flashSeparators: false,
            Key.showSeconds: true,
            Key.timeZoneIdentifier: "Asia/Shanghai",
            Key.useSystemTimeZone: false
        ])

        showDate = defaults.bool(forKey: Key.showDate)
        showWeekday = defaults.bool(forKey: Key.showWeekday)
        flashSeparators = defaults.bool(forKey: Key.flashSeparators)
        showSeconds = defaults.bool(forKey: Key.showSeconds)
        timeZoneIdentifier = defaults.string(forKey: Key.timeZoneIdentifier) ?? "Asia/Shanghai"
        useSystemTimeZone = defaults.bool(forKey: Key.useSystemTimeZone)
        recentTimeZoneIdentifiers = defaults.stringArray(forKey: Key.recentTimeZoneIdentifiers) ?? []
    }

    var effectiveTimeZone: TimeZone {
        if useSystemTimeZone {
            return .autoupdatingCurrent
        }
        return TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: "Asia/Shanghai")!
    }

    /// Date format for the menu bar title, e.g. "M月d日 EEE HH:mm:ss".
    var menuBarPattern: String {
        var parts: [String] = []
        if showDate { parts.append("M月d日") }
        if showWeekday { parts.append("EEE") }
        parts.append(showSeconds ? "HH:mm:ss" : "HH:mm")
        return parts.joined(separator: " ")
    }

    /// Switches the menu bar clock to a fixed zone and remembers it as recently used.
    func selectClockTimeZone(_ identifier: String) {
        useSystemTimeZone = false
        timeZoneIdentifier = identifier
        recentTimeZoneIdentifiers = Array(([identifier] + recentTimeZoneIdentifiers.filter { $0 != identifier }).prefix(5))
    }

    func shortTimeZoneName(_ timeZone: TimeZone) -> String {
        timeZone.localizedName(for: .generic, locale: Locale(identifier: "zh_CN")) ?? timeZone.identifier
    }

    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.changed, object: self)
    }
}

/// Reuses one DateFormatter per pattern and zone instead of building new ones every tick.
@MainActor
enum ClockFormat {
    private static var cache: [String: DateFormatter] = [:]

    static func string(_ date: Date, _ pattern: String, in timeZone: TimeZone) -> String {
        let key = "\(pattern)|\(timeZone.identifier)"
        if let formatter = cache[key] {
            return formatter.string(from: date)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        cache[key] = formatter
        return formatter.string(from: date)
    }
}
