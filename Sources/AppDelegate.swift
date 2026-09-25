import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings = ClockSettings.shared
    private var timer: Timer?
    private lazy var controlPanel: ControlPanelController = {
        let controller = ControlPanelController(
            settings: settings,
            actions: ControlPanelActions(
                checkForUpdates: { [weak self] in
                    self?.controlPanel.close()
                    NSApp.activate(ignoringOtherApps: true)
                    Updater.shared.checkForUpdates(nil)
                },
                quit: { NSApplication.shared.terminate(nil) }
            )
        )
        controller.onClose = { [weak self] in self?.statusItem.button?.highlight(false) }
        return controller
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        Updater.shared.start()
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

    /// Opening the app again from Finder shows the panel, since nano has no other window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let button = statusItem.button, !controlPanel.isOpen {
            togglePanel(button)
        }
        return true
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.toolTip = "菜单栏时钟"
        button.imagePosition = .noImage
        button.target = self
        button.action = #selector(togglePanel(_:))
        // Both buttons open the same panel: it already holds every action, so a separate menu would only repeat it.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if controlPanel.isOpen {
            controlPanel.close()
        } else if !controlPanel.justClosed {
            controlPanel.show(below: sender)
            DispatchQueue.main.async { sender.highlight(true) }
        }
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
        var title = ClockFormat.string(now, settings.menuBarPattern, in: settings.effectiveTimeZone)
        if settings.flashSeparators && Int(now.timeIntervalSince1970) % 2 == 1 {
            title = title.replacingOccurrences(of: ":", with: " ")
        }
        // Each title change re-renders the status item, so skip ticks that don't change the text (seconds hidden).
        if statusItem.button?.title != title {
            statusItem.button?.title = title
        }
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
