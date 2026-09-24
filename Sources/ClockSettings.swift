import AppKit
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
        static let announceTime = "announceTime"
        static let announceInterval = "announceInterval"
        static let soundName = "soundName"
        static let customSoundPath = "customSoundPath"
        static let timeZoneIdentifier = "timeZoneIdentifier"
        static let useSystemTimeZone = "useSystemTimeZone"
    }

    let soundChoices = ["系统声音", "Glass", "Ping", "Pop", "Tink", "无", "自定义…"]
    let timeZoneChoices = TimeZone.knownTimeZoneIdentifiers.sorted()

    @Published var showDate: Bool { didSet { save(Key.showDate, showDate) } }
    @Published var showWeekday: Bool { didSet { save(Key.showWeekday, showWeekday) } }
    @Published var flashSeparators: Bool { didSet { save(Key.flashSeparators, flashSeparators) } }
    @Published var showSeconds: Bool { didSet { save(Key.showSeconds, showSeconds) } }
    @Published var announceTime: Bool { didSet { save(Key.announceTime, announceTime) } }
    @Published var announceInterval: String { didSet { save(Key.announceInterval, announceInterval) } }
    @Published var soundName: String { didSet { save(Key.soundName, soundName) } }
    @Published var customSoundPath: String { didSet { save(Key.customSoundPath, customSoundPath) } }
    @Published var timeZoneIdentifier: String { didSet { save(Key.timeZoneIdentifier, timeZoneIdentifier) } }
    @Published var useSystemTimeZone: Bool { didSet { save(Key.useSystemTimeZone, useSystemTimeZone) } }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.showDate: true,
            Key.showWeekday: true,
            Key.flashSeparators: false,
            Key.showSeconds: true,
            Key.announceTime: false,
            Key.announceInterval: "每小时",
            Key.soundName: "系统声音",
            Key.customSoundPath: "",
            Key.timeZoneIdentifier: "Asia/Shanghai",
            Key.useSystemTimeZone: false
        ])

        showDate = defaults.bool(forKey: Key.showDate)
        showWeekday = defaults.bool(forKey: Key.showWeekday)
        flashSeparators = defaults.bool(forKey: Key.flashSeparators)
        showSeconds = defaults.bool(forKey: Key.showSeconds)
        announceTime = defaults.bool(forKey: Key.announceTime)
        announceInterval = defaults.string(forKey: Key.announceInterval) ?? "每小时"
        soundName = defaults.string(forKey: Key.soundName) ?? "系统声音"
        customSoundPath = defaults.string(forKey: Key.customSoundPath) ?? ""
        timeZoneIdentifier = defaults.string(forKey: Key.timeZoneIdentifier) ?? "Asia/Shanghai"
        useSystemTimeZone = defaults.bool(forKey: Key.useSystemTimeZone)
    }

    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.changed, object: self)
    }

    func chooseCustomSound() {
        let panel = NSOpenPanel()
        panel.title = "选择报时声音"
        panel.prompt = "选择"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        if panel.runModal() == .OK, let url = panel.url {
            customSoundPath = url.path
            soundName = "自定义…"
        }
    }
}
