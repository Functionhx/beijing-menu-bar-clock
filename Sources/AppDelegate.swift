import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let managedAppsMenu = NSMenu()
    private let settings = ClockSettings.shared
    private let ultra = UltraSettings.shared
    private var hotKeySubscription: AnyCancellable?
    private var timer: Timer?
    private var settingsWindow: NSWindow?
    private lazy var controlPanel: ControlPanelController = {
        let controller = ControlPanelController(
            settings: settings,
            actions: ControlPanelActions(
                openSettings: { [weak self] in self?.showSettings() },
                launch: { [weak self] app in
                    self?.controlPanel.close()
                    self?.settings.launch(app)
                },
                reveal: { [weak self] app in
                    self?.controlPanel.close()
                    self?.settings.reveal(app)
                },
                addApplications: { [weak self] in
                    self?.runFromPanel { $0.chooseApplications() }
                },
                chooseCustomSound: { [weak self] in
                    self?.runFromPanel { $0.chooseCustomSound() }
                },
                checkForUpdates: { [weak self] in self?.checkForUpdates() },
                quit: { [weak self] in self?.quitApp() }
            )
        )
        controller.onClose = { [weak self] in self?.statusItem.button?.highlight(false) }
        return controller
    }()
    private var lastAnnouncementMinute = ""

    /// Open/alert panels can't sit on top of the control panel, so close it and bring the app forward first.
    private func runFromPanel(_ body: @escaping (ClockSettings) -> Void) {
        controlPanel.close()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [settings] in body(settings) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureMenu()
        settings.startMonitoringApplications()
        Updater.shared.start()
        AlarmScheduler.shared.start()
        LoginItem.shared.registerOnFirstInstalledLaunch()
        GlobalHotKey.shared.action = { [weak self] in self?.toggleControlPanel() }
        hotKeySubscription = ultra.$hotKey.sink { setting in
            GlobalHotKey.shared.apply(setting)
        }
        NotificationCenter.default.addObserver(
            forName: ClockSettings.changed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateClock() }
        }
        updateClock()
        startTimer()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.toolTip = "菜单栏时钟"
        button.imagePosition = .noImage
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Left click toggles the control panel; right click (or Control-click) shows the classic menu.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            controlPanel.close()
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
            return
        }

        if !controlPanel.justClosed {
            toggleControlPanel()
        }
    }

    /// Status item click and the global hotkey both land here.
    private func toggleControlPanel() {
        guard let button = statusItem.button else { return }
        if controlPanel.isOpen {
            controlPanel.close()
            return
        }
        updateClock()
        controlPanel.show(below: button)
        DispatchQueue.main.async { button.highlight(true) }
    }

    private func configureMenu() {
        menu.delegate = self

        let options = NSMenuItem(title: "详细设置…", action: #selector(showSettings), keyEquivalent: ",")
        options.target = self
        menu.addItem(options)

        let managedApps = NSMenuItem(title: "按指定时区打开", action: nil, keyEquivalent: "")
        managedApps.submenu = managedAppsMenu
        menu.addItem(managedApps)

        let refresh = NSMenuItem(title: "刷新", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let checkForUpdates = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "")
        checkForUpdates.target = self
        menu.addItem(checkForUpdates)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出北京时间", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func startTimer() {
        timer?.invalidate()
        // Fire just after each whole second so the 0.2s tolerance never crosses into the next second.
        let nextSecond = Date(timeIntervalSinceReferenceDate: Date.timeIntervalSinceReferenceDate.rounded(.down) + 1.02)
        let timer = Timer(fire: nextSecond, interval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateClock() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func updateClock() {
        let now = Date()
        let timeZone = settings.effectiveTimeZone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone

        var parts: [String] = []
        if settings.showDate {
            formatter.dateFormat = "M月d日"
            parts.append(formatter.string(from: now))
        }
        if settings.showWeekday {
            formatter.dateFormat = "EEE"
            parts.append(formatter.string(from: now))
        }

        formatter.dateFormat = settings.showSeconds ? "HH:mm:ss" : "HH:mm"
        var time = formatter.string(from: now)
        let second = Calendar(identifier: .gregorian).dateComponents(in: timeZone, from: now).second ?? 0
        if settings.flashSeparators && second.isMultiple(of: 2) == false {
            time = time.replacingOccurrences(of: ":", with: " ")
        }
        parts.append(time)
        statusItem.button?.title = parts.joined(separator: " ")

        announceIfNeeded(now)
    }

    private func announceIfNeeded(_ date: Date) {
        guard settings.announceTime else { return }
        let timeZone = settings.effectiveTimeZone
        guard !ultra.quietHours.contains(date, in: timeZone) else { return }
        let calendar = Calendar(identifier: .gregorian)
        let values = calendar.dateComponents(in: timeZone, from: date)
        guard values.second == 0, let minute = values.minute, let hour = values.hour else { return }

        let shouldAnnounce: Bool
        switch settings.announceInterval {
        case "每刻钟": shouldAnnounce = minute.isMultiple(of: 15)
        case "每半小时": shouldAnnounce = minute.isMultiple(of: 30)
        default: shouldAnnounce = minute == 0
        }
        guard shouldAnnounce else { return }

        let key = "\(values.year ?? 0)-\(values.month ?? 0)-\(values.day ?? 0)-\(hour)-\(minute)"
        guard key != lastAnnouncementMinute else { return }
        lastAnnouncementMinute = key

        Announcer.shared.playSound(for: settings)
        Announcer.shared.speak("现在是\(Announcer.spokenTime(hour: hour, minute: minute))")
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateClock()
        rebuildManagedAppsMenu()
    }

    private func rebuildManagedAppsMenu() {
        settings.refreshApplicationStatuses()
        managedAppsMenu.removeAllItems()
        if settings.managedTimeZoneApps.isEmpty {
            let empty = NSMenuItem(title: "尚未添加应用", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            managedAppsMenu.addItem(empty)
        } else {
            for app in settings.managedTimeZoneApps {
                let status = settings.launchStatus(for: app)
                let item = NSMenuItem(
                    title: "\(app.displayName) · \(shortTimeZoneName(app.timeZoneIdentifier)) · \(status.menuLabel)",
                    action: #selector(openManagedApplication(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = app.id.uuidString
                item.image = NSWorkspace.shared.icon(forFile: app.applicationURL.path)
                item.image?.size = NSSize(width: 18, height: 18)
                managedAppsMenu.addItem(item)
            }
        }
        managedAppsMenu.addItem(.separator())
        let manage = NSMenuItem(title: "管理白名单…", action: #selector(showSettings), keyEquivalent: "")
        manage.target = self
        managedAppsMenu.addItem(manage)
    }

    private func shortTimeZoneName(_ identifier: String) -> String {
        TimeZone(identifier: identifier)?.localizedName(for: .generic, locale: Locale(identifier: "zh_CN"))
            ?? identifier
    }

    @objc private func openManagedApplication(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString),
              let app = settings.managedTimeZoneApps.first(where: { $0.id == id }) else { return }
        settings.launch(app)
    }

    @objc private func showSettings() {
        controlPanel.close()
        if settingsWindow == nil {
            let view = SettingsView(settings: settings) { [weak self] in
                self?.settingsWindow?.close()
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "详细设置"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        // Keep time fields from grabbing focus (and a highlighted hour) when the window opens.
        settingsWindow?.makeFirstResponder(nil)
    }

    @objc private func checkForUpdates() {
        controlPanel.close()
        NSApp.activate(ignoringOtherApps: true)
        Updater.shared.checkForUpdates(nil)
    }

    @objc private func refreshNow() {
        updateClock()
        startTimer()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

@main
@MainActor
struct BeijingMenuBarClockApp {
    private static let appDelegate = AppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.delegate = appDelegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
