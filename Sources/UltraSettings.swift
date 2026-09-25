import Foundation

/// Sections of the control panel.
enum PanelTab: String, CaseIterable, Identifiable {
    case clock
    case world
    case calendar
    case alarms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "时钟"
        case .world: return "世界"
        case .calendar: return "日历"
        case .alarms: return "闹钟"
        }
    }

    var symbolName: String {
        switch self {
        case .clock: return "clock"
        case .world: return "globe.asia.australia"
        case .calendar: return "calendar"
        case .alarms: return "alarm"
        }
    }
}

/// Persistent state of the ultra-only features. The original clock settings stay in `ClockSettings`.
@MainActor
final class UltraSettings: ObservableObject {
    static let shared = UltraSettings()

    private enum Key {
        static let panelTab = "ultra.panelTab"
        static let worldClocks = "ultra.worldClocks"
        static let workSchedule = "ultra.workSchedule"
        static let showsWorkStatus = "ultra.showsWorkStatus"
        static let quietHours = "ultra.quietHours"
        static let alarms = "ultra.alarms"
        static let hotKey = "ultra.hotKey"
    }

    @Published var panelTab: PanelTab { didSet { defaults.set(panelTab.rawValue, forKey: Key.panelTab) } }
    @Published var worldClocks: [WorldClockCity] { didSet { store(worldClocks, Key.worldClocks) } }
    @Published var workSchedule: WorkSchedule { didSet { store(workSchedule, Key.workSchedule) } }
    @Published var showsWorkStatus: Bool { didSet { defaults.set(showsWorkStatus, forKey: Key.showsWorkStatus) } }
    @Published var quietHours: QuietHours { didSet { store(quietHours, Key.quietHours) } }
    @Published var alarms: [Alarm] { didSet { store(alarms, Key.alarms) } }
    @Published var hotKey: HotKeySetting { didSet { store(hotKey, Key.hotKey) } }

    private let defaults = UserDefaults.standard

    private init() {
        panelTab = defaults.string(forKey: Key.panelTab).flatMap(PanelTab.init(rawValue:)) ?? .clock
        worldClocks = Self.load(Key.worldClocks, from: defaults) ?? [
            WorldClockCity(timeZoneIdentifier: "America/Los_Angeles"),
            WorldClockCity(timeZoneIdentifier: "America/New_York"),
            WorldClockCity(timeZoneIdentifier: "Europe/London")
        ]
        workSchedule = Self.load(Key.workSchedule, from: defaults) ?? WorkSchedule()
        showsWorkStatus = defaults.object(forKey: Key.showsWorkStatus) as? Bool ?? true
        quietHours = Self.load(Key.quietHours, from: defaults) ?? QuietHours()
        alarms = Self.load(Key.alarms, from: defaults) ?? []
        hotKey = Self.load(Key.hotKey, from: defaults) ?? HotKeySetting()
    }

    // MARK: World clock

    func addWorldClock(_ identifier: String) {
        guard !worldClocks.contains(where: { $0.timeZoneIdentifier == identifier }) else { return }
        worldClocks.append(WorldClockCity(timeZoneIdentifier: identifier))
    }

    func removeWorldClock(id: UUID) {
        worldClocks.removeAll { $0.id == id }
    }

    /// Moves a city up (−1) or down (+1).
    func moveWorldClock(id: UUID, by delta: Int) {
        guard let index = worldClocks.firstIndex(where: { $0.id == id }) else { return }
        let target = index + delta
        guard worldClocks.indices.contains(target) else { return }
        worldClocks.swapAt(index, target)
    }

    // MARK: Alarms

    func saveAlarm(_ alarm: Alarm) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
        } else {
            alarms.append(alarm)
        }
        alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    func removeAlarm(id: UUID) {
        alarms.removeAll { $0.id == id }
    }

    func setAlarm(id: UUID, enabled: Bool) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[index].isEnabled = enabled
    }

    // MARK: Persistence

    private func store<Value: Encodable>(_ value: Value, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load<Value: Decodable>(_ key: String, from defaults: UserDefaults) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }
}
