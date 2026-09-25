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
        static let managedTimeZoneApps = "managedTimeZoneApps"
    }

    let soundChoices = ["系统声音", "Glass", "Ping", "Pop", "Tink", "无", "自定义…"]
    let announceIntervalChoices = ["每小时", "每半小时", "每刻钟"]
    let timeZoneChoices = TimeZone.knownTimeZoneIdentifiers.sorted()
    let quickTimeZoneChoices = [
        "Asia/Shanghai", "Asia/Hong_Kong", "Asia/Taipei", "Asia/Tokyo", "Asia/Singapore",
        "Europe/London", "Europe/Paris", "America/New_York", "America/Los_Angeles"
    ]

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
    @Published var managedTimeZoneApps: [ManagedTimeZoneApp] {
        didSet {
            saveManagedApps()
            NotificationCenter.default.post(name: Self.changed, object: self)
        }
    }
    @Published private(set) var applicationStatusRevision = 0

    private let defaults = UserDefaults.standard
    private var workspaceObservers: [NSObjectProtocol] = []
    private var automaticRestartingBundleIdentifiers: Set<String> = []

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

        if let data = defaults.data(forKey: Key.managedTimeZoneApps),
           let storedApps = try? JSONDecoder().decode([ManagedTimeZoneApp].self, from: data) {
            managedTimeZoneApps = storedApps
        } else {
            managedTimeZoneApps = Self.defaultManagedApps()
            saveManagedApps()
        }
    }

    var effectiveTimeZone: TimeZone {
        if useSystemTimeZone {
            return .autoupdatingCurrent
        }
        return TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: "Asia/Shanghai")!
    }

    func shortTimeZoneName(_ timeZone: TimeZone) -> String {
        timeZone.localizedName(for: .generic, locale: Locale(identifier: "zh_CN")) ?? timeZone.identifier
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

    func chooseApplications() {
        let panel = NSOpenPanel()
        panel.title = "添加到应用时区白名单"
        panel.prompt = "添加"
        panel.message = "选中的应用将从北京时间菜单中按指定时区启动。"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            addApplication(at: url)
        }
    }

    func removeApplication(id: UUID) {
        managedTimeZoneApps.removeAll { $0.id == id }
    }

    func toggleAutomaticLaunchManagement(for id: UUID) {
        guard let index = managedTimeZoneApps.firstIndex(where: { $0.id == id }) else { return }
        managedTimeZoneApps[index].automaticallyManageLaunches.toggle()
    }

    var allApplicationsAutomaticallyManaged: Bool {
        !managedTimeZoneApps.isEmpty && managedTimeZoneApps.allSatisfy(\.automaticallyManageLaunches)
    }

    func setAutomaticLaunchManagementForAll(_ enabled: Bool) {
        for index in managedTimeZoneApps.indices {
            managedTimeZoneApps[index].automaticallyManageLaunches = enabled
        }
    }

    func isRunning(_ app: ManagedTimeZoneApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty
    }

    func startMonitoringApplications() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let launched = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let runningApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                self?.applicationDidLaunch(runningApplication)
            }
        }
        let terminated = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshApplicationStatuses()
            }
        }
        workspaceObservers = [launched, terminated]
    }

    func refreshApplicationStatuses() {
        applicationStatusRevision &+= 1
    }

    func launchStatus(for app: ManagedTimeZoneApp) -> ManagedAppLaunchStatus {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)
        guard !runningApps.isEmpty else { return .notRunning }

        var readAtLeastOneEnvironment = false
        for runningApp in runningApps {
            guard let environment = ProcessEnvironmentReader.environment(for: runningApp.processIdentifier) else {
                continue
            }
            readAtLeastOneEnvironment = true
            guard environment["BEIJING_CLOCK_MANAGED"] == "1" else { continue }

            let actualTimeZone = environment["BEIJING_CLOCK_TIME_ZONE"] ?? environment["TZ"] ?? "未知"
            if actualTimeZone == app.timeZoneIdentifier {
                return .applied(actualTimeZone)
            }
            return .mismatched(actual: actualTimeZone)
        }
        return readAtLeastOneEnvironment ? .notApplied : .unavailable
    }

    func launch(_ app: ManagedTimeZoneApp) {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)
        if runningApps.isEmpty {
            open(app)
            return
        }

        let alert = NSAlert()
        alert.messageText = "重新打开“\(app.displayName)”？"
        alert.informativeText = "应用必须完全退出后，新的时区 \(app.timeZoneIdentifier) 才会生效。未保存的内容可能丢失。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "退出并重新打开")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        for runningApp in runningApps {
            runningApp.terminate()
        }
        waitUntilStoppedAndOpen(app, attemptsRemaining: 50)
    }

    func reveal(_ app: ManagedTimeZoneApp) {
        NSWorkspace.shared.activateFileViewerSelecting([app.applicationURL])
    }

    func timeZoneLabel(_ identifier: String) -> String {
        guard let zone = TimeZone(identifier: identifier) else { return identifier }
        let name = zone.localizedName(for: .generic, locale: Locale(identifier: "zh_CN")) ?? identifier
        return "\(name) — \(identifier)"
    }

    private func addApplication(at url: URL) {
        guard let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier else {
            showError(title: "无法添加应用", message: "没有找到这个应用的标识符。")
            return
        }

        if let index = managedTimeZoneApps.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) {
            managedTimeZoneApps[index].applicationPath = url.path
            return
        }

        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        managedTimeZoneApps.append(
            ManagedTimeZoneApp(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                applicationPath: url.path
            )
        )
    }

    private func waitUntilStoppedAndOpen(_ app: ManagedTimeZoneApp, attemptsRemaining: Int) {
        guard !isRunning(app) else {
            guard attemptsRemaining > 0 else {
                showError(
                    title: "“\(app.displayName)”仍在运行",
                    message: "请手动退出应用，再从北京时间菜单重新打开。"
                )
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.waitUntilStoppedAndOpen(app, attemptsRemaining: attemptsRemaining - 1)
            }
            return
        }
        open(app)
    }

    private func open(_ app: ManagedTimeZoneApp) {
        let url = app.applicationURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            showError(title: "找不到“\(app.displayName)”", message: "请移除后重新添加这个应用。")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.environment = [
            "TZ": app.timeZoneIdentifier,
            "BEIJING_CLOCK_MANAGED": "1",
            "BEIJING_CLOCK_TIME_ZONE": app.timeZoneIdentifier
        ]
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                self?.refreshApplicationStatuses()
                if let error {
                    self?.automaticRestartingBundleIdentifiers.remove(app.bundleIdentifier)
                    self?.showError(title: "无法打开“\(app.displayName)”", message: error.localizedDescription)
                }
            }
        }
    }

    private func applicationDidLaunch(_ runningApplication: NSRunningApplication) {
        refreshApplicationStatuses()
        guard let bundleIdentifier = runningApplication.bundleIdentifier,
              let app = managedTimeZoneApps.first(where: {
                  $0.bundleIdentifier == bundleIdentifier && $0.automaticallyManageLaunches
              }) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            let status = self.launchStatus(for: app)

            if self.automaticRestartingBundleIdentifiers.contains(bundleIdentifier) {
                self.automaticRestartingBundleIdentifiers.remove(bundleIdentifier)
                self.refreshApplicationStatuses()
                return
            }

            guard status == .notApplied else { return }
            self.automaticRestartingBundleIdentifiers.insert(bundleIdentifier)
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            for runningApp in runningApps {
                runningApp.terminate()
            }
            self.waitUntilStoppedAndOpen(app, attemptsRemaining: 50)
        }
    }

    private func saveManagedApps() {
        guard let data = try? JSONEncoder().encode(managedTimeZoneApps) else { return }
        defaults.set(data, forKey: Key.managedTimeZoneApps)
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private static func defaultManagedApps() -> [ManagedTimeZoneApp] {
        let candidates = [
            "/System/Applications/Notes.app",
            "/Applications/WeChat.app",
            "/Applications/QQ.app"
        ]
        return candidates.compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return nil }
            let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            return ManagedTimeZoneApp(
                bundleIdentifier: identifier,
                displayName: displayName,
                applicationPath: path
            )
        }
    }
}
