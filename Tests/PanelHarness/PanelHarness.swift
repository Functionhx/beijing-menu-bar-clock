import AppKit
import SwiftUI

/// Test-only host for the control panel (not part of the app target). Runs unbundled, so it has its own
/// UserDefaults domain and can't touch the installed app's settings or LaunchAgent.
///
/// Arguments:
///   --expand clock-zone        open with the clock time zone search expanded
///   --clicks "x,y;x,y"         clicks in points from the panel's top-left, 0.8s apart; a step "type:text"
///                              types text into the focused field instead
///   --shot path.png            screenshot of the panel window after the clicks
///   --appearance dark
///   --seed-dates               replace the important dates with a fixed sample set
///   --reset                    start from default settings
///   --settings page            open 详细设置 on a page (e.g. importantDates) and screenshot it to --shot
/// After every click it prints the settings, so tests can assert on them.
@main @MainActor struct PanelHarness {
    static var item: NSStatusItem!
    static var controller: ControlPanelController!
    static var settingsWindow: SettingsWindowController?

    static func arg(_ name: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--" + name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if arg("appearance") == "dark" { app.appearance = NSAppearance(named: .darkAqua) }
        if CommandLine.arguments.contains("--reset"), let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName as String? {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        let settings = ClockSettings.shared
        if CommandLine.arguments.contains("--seed-dates") { seedDates() }
        if let page = arg("settings").flatMap(SettingsPage.init(rawValue:)) {
            settingsWindow = SettingsWindowController(settings: settings, initialPage: page, onCheckForUpdates: {})
            settingsWindow?.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if let path = arg("shot"), let window = settingsWindow?.window {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    p.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", path]
                    try? p.run(); p.waitUntilExit()
                }
                exit(0)
            }
            app.run()
            return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "HARNESS"
        controller = ControlPanelController(settings: settings, actions: ControlPanelActions(
            openSettings: {}, launch: { _ in }, reveal: { _ in }, addApplications: {}, chooseCustomSound: {},
            checkForUpdates: {}, openImportantDates: {}, quit: {}))

        let expansion: ControlPanelView.Expansion? = arg("expand") == "clock-zone" ? .clockTimeZone() : nil
        let clicks: [Step] = (arg("clicks") ?? "").split(separator: ";").map { step in
            if step.hasPrefix("type:") { return .type(String(step.dropFirst(5))) }
            let v = step.split(separator: ",").map { Double($0)! }
            return .click(CGPoint(x: v[0], y: v[1]))
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            controller.show(below: item.button!, expanding: expansion)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            guard let panel = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }) else {
                print("ERROR panel closed (a real click elsewhere dismisses it); rerun")
                exit(3)
            }
            printState("start", panel)
            run(clicks[...], panel)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { print("ERROR timeout"); exit(2) }
        app.run()
    }

    enum Step {
        case click(CGPoint)
        case type(String)
    }

    static func run(_ clicks: ArraySlice<Step>, _ panel: NSWindow) {
        guard let step = clicks.first else {
            if let path = arg("shot") {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                p.arguments = ["-x", "-o", "-l", "\(panel.windowNumber)", path]
                try? p.run(); p.waitUntilExit()
            }
            exit(panel.isVisible ? 0 : 3)
        }
        let label: String
        switch step {
        case let .click(point):
            label = "click \(Int(point.x)),\(Int(point.y))"
            let location = NSPoint(x: point.x, y: panel.frame.height - point.y)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                NSApp.postEvent(NSEvent.mouseEvent(
                    with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!, atStart: false)
            }
        case let .type(text):
            label = "type \(text)"
            for character in text {
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    NSApp.postEvent(NSEvent.keyEvent(
                        with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: panel.windowNumber, context: nil, characters: String(character),
                        charactersIgnoringModifiers: String(character), isARepeat: false, keyCode: 0)!, atStart: false)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            printState(label, panel)
            run(clicks.dropFirst(), panel)
        }
    }

    static func printState(_ label: String, _ panel: NSWindow) {
        let s = ClockSettings.shared
        let bits = [s.showDate, s.showWeekday, s.showSeconds, s.flashSeparators].map { $0 ? "1" : "0" }.joined()
        let dates = ImportantDateStore.shared.items.map(\.title).joined(separator: ",")
        print("\(label): height=\(Int(panel.frame.height)) toggles=\(bits) zone=\(s.timeZoneIdentifier) dates=[\(dates)]")
    }

    static func seedDates() {
        let store = ImportantDateStore.shared
        for item in store.items { store.remove(id: item.id) }
        let d = DayStamp.init(year:month:day:)
        store.save(ImportantDate(title: "考研报名", kind: .deadline, start: d(2026, 10, 10), end: d(2026, 10, 31)))
        store.save(ImportantDate(title: "考研初试", kind: .exam, start: d(2026, 12, 20), minuteOfDay: 8 * 60 + 30, reminderDays: [1, 7, 30]))
        store.save(ImportantDate(title: "妈妈生日", kind: .birthday, start: d(1968, 8, 28), repeatsYearly: true, isLunar: true))
        store.save(ImportantDate(title: "在一起纪念日", kind: .anniversary, start: d(2021, 10, 1), repeatsYearly: true))
    }
}
