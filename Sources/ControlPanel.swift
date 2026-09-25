import AppKit
import SwiftUI

struct ControlPanelActions {
    let openSettings: () -> Void
    let launch: (ManagedTimeZoneApp) -> Void
    let quit: () -> Void
}

private final class ControlPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        (delegate as? ControlPanelController)?.close()
    }
}

/// Control Center–style panel that drops down from the status item on left click.
@MainActor
final class ControlPanelController: NSObject, NSWindowDelegate {
    private let panel: ControlPanelWindow
    private let hostingView: NSHostingView<ControlPanelView>
    private let settings: ClockSettings
    private var outsideClickMonitor: Any?
    private var lastClosed = Date.distantPast
    private(set) var isOpen = false
    var onClose: (() -> Void)?

    init(settings: ClockSettings, actions: ControlPanelActions) {
        self.settings = settings
        hostingView = NSHostingView(rootView: ControlPanelView(settings: settings, actions: actions))
        panel = ControlPanelWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.contentView = makeBackground(containing: hostingView)
    }

    /// True right after the panel closed, so the same status item click that dismissed it doesn't reopen it.
    var justClosed: Bool { Date().timeIntervalSince(lastClosed) < 0.25 }

    func show(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }

        settings.refreshApplicationStatuses()
        let size = hostingView.fittingSize
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let y = min(anchor.minY, visible.maxY) - size.height - 6

        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)
        isOpen = true

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        lastClosed = Date()
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        panel.orderOut(nil)
        onClose?()
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func makeBackground(containing content: NSView) -> NSView {
        let cornerRadius: CGFloat = 18
        content.autoresizingMask = [.width, .height]

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            // The glass draws its own rounded shadow; the window shadow would be rectangular.
            panel.hasShadow = false
            return glass
        }

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: cornerRadius)
        effect.addSubview(content)
        return effect
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

struct ControlPanelView: View {
    @ObservedObject var settings: ClockSettings
    let actions: ControlPanelActions

    private let chinese = Locale(identifier: "zh_CN")

    var body: some View {
        VStack(spacing: 10) {
            header

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                ToggleTile(title: "日期", symbol: "calendar", isOn: $settings.showDate)
                ToggleTile(title: "星期", symbol: "calendar.badge.clock", isOn: $settings.showWeekday)
                ToggleTile(title: "秒钟", symbol: "stopwatch", isOn: $settings.showSeconds)
                ToggleTile(title: "闪动分隔符", symbol: "sparkles", isOn: $settings.flashSeparators)
            }

            timeZoneModule
            announcementModule
            applicationsModule
            footer
        }
        .padding(12)
        .frame(width: 320)
    }

    private var header: some View {
        // Tick on whole seconds, matching the menu bar clock.
        let start = Date(timeIntervalSinceReferenceDate: Date.timeIntervalSinceReferenceDate.rounded(.down))
        return TimelineView(.periodic(from: start, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(format(context.date, "HH:mm:ss"))
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                Text("\(format(context.date, "M月d日 EEEE")) · \(settings.shortTimeZoneName(settings.effectiveTimeZone))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 2)
        }
    }

    private var timeZoneModule: some View {
        HStack(spacing: 10) {
            Button {
                settings.useSystemTimeZone.toggle()
            } label: {
                ToggleCircle(symbol: "location.fill", isOn: settings.useSystemTimeZone)
            }
            .buttonStyle(.plain)
            .help("跟随系统时区")

            TileLabel(
                title: "时区",
                subtitle: settings.useSystemTimeZone
                    ? "跟随系统 · \(settings.shortTimeZoneName(settings.effectiveTimeZone))"
                    : settings.shortTimeZoneName(settings.effectiveTimeZone)
            )

            Spacer(minLength: 4)

            Menu("切换") {
                ForEach(quickTimeZones, id: \.self) { identifier in
                    Button {
                        settings.useSystemTimeZone = false
                        settings.timeZoneIdentifier = identifier
                    } label: {
                        if !settings.useSystemTimeZone && identifier == settings.timeZoneIdentifier {
                            Label(settings.timeZoneLabel(identifier), systemImage: "checkmark")
                        } else {
                            Text(settings.timeZoneLabel(identifier))
                        }
                    }
                }
                Divider()
                Button("更多时区…", action: actions.openSettings)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(8)
        .moduleBackground()
    }

    private var quickTimeZones: [String] {
        let choices = settings.quickTimeZoneChoices
        return choices.contains(settings.timeZoneIdentifier) ? choices : [settings.timeZoneIdentifier] + choices
    }

    private var announcementModule: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    settings.announceTime.toggle()
                } label: {
                    ToggleCircle(
                        symbol: settings.announceTime ? "speaker.wave.2.fill" : "speaker.slash.fill",
                        isOn: settings.announceTime
                    )
                }
                .buttonStyle(.plain)

                TileLabel(
                    title: "语音报时",
                    subtitle: settings.announceTime ? "\(settings.announceInterval) · \(settings.soundName)" : "关"
                )
                Spacer(minLength: 0)
            }

            Picker("时间间隔", selection: $settings.announceInterval) {
                ForEach(settings.announceIntervalChoices, id: \.self) { interval in
                    Text(interval).tag(interval)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!settings.announceTime)
        }
        .padding(8)
        .moduleBackground()
    }

    private var applicationsModule: some View {
        let _ = settings.applicationStatusRevision
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("按指定时区打开")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("管理…", action: actions.openSettings)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if settings.managedTimeZoneApps.isEmpty {
                Text("尚未添加应用")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 6)], spacing: 8) {
                    ForEach(settings.managedTimeZoneApps) { app in
                        applicationCell(app)
                    }
                }
            }
        }
        .padding(8)
        .moduleBackground()
    }

    private func applicationCell(_ app: ManagedTimeZoneApp) -> some View {
        let status = settings.launchStatus(for: app)
        let zone = TimeZone(identifier: app.timeZoneIdentifier).map(settings.shortTimeZoneName) ?? app.timeZoneIdentifier
        return Button {
            actions.launch(app)
        } label: {
            VStack(spacing: 3) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.applicationURL.path))
                    .resizable()
                    .frame(width: 32, height: 32)
                    .overlay(alignment: .bottomTrailing) {
                        if let color = statusColor(status) {
                            Circle()
                                .fill(color)
                                .frame(width: 8, height: 8)
                                .overlay(Circle().stroke(.background, lineWidth: 1.5))
                        }
                    }
                Text(app.displayName)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(app.displayName) · \(zone) · \(status.menuLabel)")
    }

    private var footer: some View {
        HStack {
            Button("时钟选项…", action: actions.openSettings)
            Spacer()
            Button("退出", action: actions.quit)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
    }

    private func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = chinese
        formatter.timeZone = settings.effectiveTimeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private func statusColor(_ status: ManagedAppLaunchStatus) -> Color? {
        switch status {
        case .applied: return .green
        case .notApplied, .mismatched: return .orange
        case .notRunning, .unavailable: return nil
        }
    }
}

private struct ToggleTile: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                ToggleCircle(symbol: symbol, isOn: isOn)
                TileLabel(title: title, subtitle: isOn ? "开" : "关")
                Spacer(minLength: 0)
            }
            .padding(8)
            .moduleBackground()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ToggleCircle: View {
    let symbol: String
    let isOn: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .frame(width: 28, height: 28)
            .background(Circle().fill(isOn ? Color.accentColor : Color.primary.opacity(0.1)))
            .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

private struct TileLabel: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct ModuleBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.45))
        )
    }
}

private extension View {
    func moduleBackground() -> some View {
        modifier(ModuleBackground())
    }
}
