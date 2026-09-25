import AppKit
import SwiftUI

/// Test-only host for the control panel (not part of the app target). Runs unbundled, so it has its own
/// UserDefaults domain and can't touch the installed app's settings or LaunchAgent.
///
/// Arguments:
///   --expand clock-zone        open with the clock time zone search expanded
///   --clicks "x,y;x,y"         clicks in points from the panel's top-left, 0.8s apart
///   --shot path.png            screenshot of the panel window after the clicks
///   --appearance dark
/// After every click it prints the settings, so tests can assert on them.
@main @MainActor struct PanelHarness {
    static var item: NSStatusItem!
    static var controller: ControlPanelController!

    static func arg(_ name: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--" + name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if arg("appearance") == "dark" { app.appearance = NSAppearance(named: .darkAqua) }
        let settings = ClockSettings.shared
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "HARNESS"
        controller = ControlPanelController(settings: settings, actions: ControlPanelActions(
            openSettings: {}, launch: { _ in }, reveal: { _ in }, addApplications: {}, chooseCustomSound: {},
            checkForUpdates: {}, quit: {}))

        let expansion: ControlPanelView.Expansion? = arg("expand") == "clock-zone" ? .clockTimeZone() : nil
        let clicks: [CGPoint] = (arg("clicks") ?? "").split(separator: ";").map { pair in
            let v = pair.split(separator: ",").map { Double($0)! }
            return CGPoint(x: v[0], y: v[1])
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

    static func run(_ clicks: ArraySlice<CGPoint>, _ panel: NSWindow) {
        guard let point = clicks.first else {
            if let path = arg("shot") {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                p.arguments = ["-x", "-o", "-l", "\(panel.windowNumber)", path]
                try? p.run(); p.waitUntilExit()
            }
            exit(panel.isVisible ? 0 : 3)
        }
        let location = NSPoint(x: point.x, y: panel.frame.height - point.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            NSApp.postEvent(NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!, atStart: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            printState("click \(Int(point.x)),\(Int(point.y))", panel)
            run(clicks.dropFirst(), panel)
        }
    }

    static func printState(_ label: String, _ panel: NSWindow) {
        let s = ClockSettings.shared
        let bits = [s.showDate, s.showWeekday, s.showSeconds, s.flashSeparators].map { $0 ? "1" : "0" }.joined()
        print("\(label): height=\(Int(panel.frame.height)) toggles=\(bits) zone=\(s.timeZoneIdentifier)")
    }
}
