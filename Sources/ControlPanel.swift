import AppKit
import SwiftUI

struct ControlPanelActions {
    let checkForUpdates: () -> Void
    let quit: () -> Void
}

private final class ControlPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        (delegate as? ControlPanelController)?.close()
    }
}

/// Hosting view that reports SwiftUI size changes so the panel can grow and shrink with its content.
private final class ResizingHostingView<Content: View>: NSHostingView<Content> {
    var onIntrinsicSizeChange: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onIntrinsicSizeChange?()
    }
}

/// Glass panel that drops down from the status item.
@MainActor
final class ControlPanelController: NSObject, NSWindowDelegate {
    private let panel: ControlPanelWindow
    private let hostingView: ResizingHostingView<ControlPanelView>
    private let settings: ClockSettings
    private let actions: ControlPanelActions
    private var outsideClickMonitor: Any?
    private var lastClosed = Date.distantPast
    private var session = 0
    private var resizeScheduled = false
    private(set) var isOpen = false
    var onClose: (() -> Void)?

    init(settings: ClockSettings, actions: ControlPanelActions) {
        self.settings = settings
        self.actions = actions
        hostingView = ResizingHostingView(rootView: ControlPanelView(settings: settings, actions: actions))
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
        hostingView.onIntrinsicSizeChange = { [weak self] in self?.scheduleResize() }
    }

    /// True right after the panel closed, so the same status item click that dismissed it doesn't reopen it.
    var justClosed: Bool { Date().timeIntervalSince(lastClosed) < 0.25 }

    func show(below button: NSStatusBarButton, searching: Bool = false) {
        guard let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }

        // A fresh view identity each time, so the search starts collapsed.
        session += 1
        hostingView.rootView = ControlPanelView(settings: settings, actions: actions, session: session, searching: searching)
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let y = min(anchor.minY, visible.maxY) - size.height - 6

        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
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

    private func scheduleResize() {
        guard isOpen, !resizeScheduled else { return }
        resizeScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resizeScheduled = false
            guard self.isOpen else { return }
            let size = self.hostingView.fittingSize
            var frame = self.panel.frame
            guard abs(frame.height - size.height) > 0.5 else { return }
            // Keep the top edge pinned under the menu bar.
            frame.origin.y = frame.maxY - size.height
            frame.size.height = size.height
            self.panel.setFrame(frame, display: true)
            self.panel.invalidateShadow()
        }
    }

    private func makeBackground(containing content: NSView) -> NSView {
        let cornerRadius: CGFloat = 16
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
    let settings: ClockSettings
    let actions: ControlPanelActions
    var session = 0
    var searching = false

    var body: some View {
        ControlPanelContent(settings: settings, actions: actions, searching: searching)
            .id(session)
    }
}

private struct ControlPanelContent: View {
    @ObservedObject var settings: ClockSettings
    let actions: ControlPanelActions
    @State var searching: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            HStack(spacing: 6) {
                ToggleCapsule(title: "日期", symbol: "calendar", isOn: $settings.showDate)
                ToggleCapsule(title: "星期", symbol: "calendar.day.timeline.left", isOn: $settings.showWeekday)
                ToggleCapsule(title: "秒", symbol: "stopwatch", isOn: $settings.showSeconds)
                ToggleCapsule(title: "闪动", symbol: "sparkles", isOn: $settings.flashSeparators)
            }

            timeZoneCard

            HStack {
                Button("检查更新…", action: actions.checkForUpdates)
                Spacer()
                Button("退出", action: actions.quit)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
        .padding(12)
        .frame(width: 260)
    }

    private var header: some View {
        // Tick on whole seconds, matching the menu bar clock.
        let start = Date(timeIntervalSinceReferenceDate: Date.timeIntervalSinceReferenceDate.rounded(.down))
        return TimelineView(.periodic(from: start, by: 1)) { context in
            let zone = settings.effectiveTimeZone
            VStack(alignment: .leading, spacing: 1) {
                Text(ClockFormat.string(context.date, "HH:mm:ss", in: zone))
                    .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                Text("\(ClockFormat.string(context.date, "M月d日 EEEE", in: zone)) · \(settings.shortTimeZoneName(zone))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
    }

    private var timeZoneCard: some View {
        let zone = settings.effectiveTimeZone
        let title = settings.useSystemTimeZone ? "跟随系统" : TimeZoneSearch.entry(for: settings.timeZoneIdentifier).title
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    settings.useSystemTimeZone.toggle()
                } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(settings.useSystemTimeZone ? Color.white : Color.primary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(settings.useSystemTimeZone ? Color.accentColor : Color.primary.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("跟随系统时区")

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(TimeZoneSearch.offsetLabel(seconds: zone.secondsFromGMT()))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)

                Spacer(minLength: 4)

                Image(systemName: searching ? "xmark" : "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .contentShape(Rectangle())
            .onTapGesture { searching.toggle() }

            if searching {
                TimeZoneSearchView(
                    current: settings.useSystemTimeZone ? nil : settings.timeZoneIdentifier,
                    recents: settings.recentTimeZoneIdentifiers,
                    suggestions: settings.quickTimeZoneChoices,
                    listHeight: 180,
                    onSelect: { identifier in
                        settings.selectClockTimeZone(identifier)
                        searching = false
                    },
                    onCancel: { searching = false }
                )
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

private struct ToggleCapsule: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 26)
            .background(Capsule().fill(isOn ? Color.accentColor : Color.primary.opacity(0.08)))
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.15), value: isOn)
        }
        .buttonStyle(.plain)
        .help(title)
    }
}
