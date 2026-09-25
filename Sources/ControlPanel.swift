import AppKit
import SwiftUI

struct ControlPanelActions {
    let openSettings: () -> Void
    let launch: (ManagedTimeZoneApp) -> Void
    let reveal: (ManagedTimeZoneApp) -> Void
    let addApplications: () -> Void
    let chooseCustomSound: () -> Void
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

/// Control Center–style panel that drops down from the status item on left click.
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

    /// Shows the panel under the status item, optionally with a section already expanded (e.g. time zone search).
    func show(below button: NSStatusBarButton, expanding expansion: ControlPanelView.Expansion? = nil) {
        guard let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }

        // A fresh view identity each time, so searches and sub-pages start collapsed.
        session += 1
        hostingView.rootView = ControlPanelView(
            settings: settings,
            actions: actions,
            session: session,
            initialExpansion: expansion
        )
        settings.refreshApplicationStatuses()
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
        let cornerRadius: CGFloat = 18
        content.autoresizingMask = [.width, .height]

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
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
    enum Expansion: Equatable {
        case clockTimeZone(query: String = "")
        case applicationTimeZone(UUID)
    }

    let settings: ClockSettings
    let actions: ControlPanelActions
    var session = 0
    var initialExpansion: Expansion?

    var body: some View {
        ControlPanelContent(settings: settings, actions: actions, expansion: initialExpansion)
            .id(session)
    }
}

private struct ControlPanelContent: View {
    @ObservedObject var settings: ClockSettings
    let actions: ControlPanelActions
    @State var expansion: ControlPanelView.Expansion?

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

    // MARK: Time zone

    private var isSearchingClockZone: Bool {
        if case .clockTimeZone = expansion { return true }
        return false
    }

    private var timeZoneModule: some View {
        VStack(spacing: 8) {
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
                        : "\(zoneTitle(settings.timeZoneIdentifier)) · \(settings.shortTimeZoneName(settings.effectiveTimeZone))"
                )

                Spacer(minLength: 4)

                PillButton(
                    title: isSearchingClockZone ? "完成" : "搜索",
                    symbol: isSearchingClockZone ? nil : "magnifyingglass"
                ) {
                    expansion = isSearchingClockZone ? nil : .clockTimeZone()
                }
            }

            if case let .clockTimeZone(query) = expansion {
                TimeZoneSearchView(
                    current: settings.useSystemTimeZone ? nil : settings.timeZoneIdentifier,
                    recents: settings.recentTimeZoneIdentifiers,
                    suggestions: settings.quickTimeZoneChoices,
                    initialQuery: query,
                    onSelect: { identifier in
                        settings.selectClockTimeZone(identifier)
                        expansion = nil
                    },
                    onCancel: { expansion = nil }
                )
            }
        }
        .padding(8)
        .moduleBackground()
    }

    private func zoneTitle(_ identifier: String) -> String {
        TimeZoneSearch.entry(for: identifier).title
    }

    // MARK: Announcement

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

                TileLabel(title: "语音报时", subtitle: settings.announceTime ? settings.announceInterval : "关")
                Spacer(minLength: 4)

                Menu {
                    ForEach(settings.soundChoices, id: \.self) { sound in
                        Button {
                            if sound == "自定义…" {
                                actions.chooseCustomSound()
                            } else {
                                settings.soundName = sound
                            }
                        } label: {
                            if sound == settings.soundName {
                                Label(soundMenuTitle(sound), systemImage: "checkmark")
                            } else {
                                Text(soundMenuTitle(sound))
                            }
                        }
                    }
                } label: {
                    Label(soundLabel, systemImage: "bell")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(!settings.announceTime)
                .help("报时声音")
            }

            Picker("时间间隔", selection: $settings.announceInterval) {
                ForEach(settings.announceIntervalChoices, id: \.self) { interval in
                    Text(interval).tag(interval)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .disabled(!settings.announceTime)
        }
        .padding(8)
        .moduleBackground()
    }

    private var soundLabel: String {
        guard settings.soundName == "自定义…" else { return settings.soundName }
        guard !settings.customSoundPath.isEmpty else { return "自定义" }
        return URL(fileURLWithPath: settings.customSoundPath).deletingPathExtension().lastPathComponent
    }

    private func soundMenuTitle(_ sound: String) -> String {
        guard sound == "自定义…", !settings.customSoundPath.isEmpty else { return sound }
        return "自定义：\(URL(fileURLWithPath: settings.customSoundPath).lastPathComponent)…"
    }

    // MARK: Applications

    private var editingApplication: ManagedTimeZoneApp? {
        guard case let .applicationTimeZone(id) = expansion else { return nil }
        return settings.managedTimeZoneApps.first { $0.id == id }
    }

    private var applicationsModule: some View {
        let _ = settings.applicationStatusRevision
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("按指定时区打开")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Toggle("自动接管", isOn: Binding(
                    get: { settings.allApplicationsAutomaticallyManaged },
                    set: { settings.setAutomaticLaunchManagementForAll($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .disabled(settings.managedTimeZoneApps.isEmpty)
                .help("开启后，从 Dock 或访达打开的白名单应用也会被自动切换到指定时区")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 6)], spacing: 8) {
                ForEach(settings.managedTimeZoneApps) { app in
                    applicationCell(app)
                }
                addApplicationCell
            }

            if let app = editingApplication {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    Text("为「\(app.displayName)」选择时区")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TimeZoneSearchView(
                        current: app.timeZoneIdentifier,
                        recents: settings.recentTimeZoneIdentifiers,
                        suggestions: settings.quickTimeZoneChoices,
                        listHeight: 168,
                        onSelect: { identifier in
                            settings.setTimeZone(identifier, forApplication: app.id)
                            expansion = nil
                        },
                        onCancel: { expansion = nil }
                    )
                }
            } else {
                Text(settings.managedTimeZoneApps.isEmpty ? "添加应用后，点按即可按指定时区打开" : "点按打开 · 右键更改时区或自动接管")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(8)
        .moduleBackground()
    }

    private func applicationCell(_ app: ManagedTimeZoneApp) -> some View {
        let status = settings.launchStatus(for: app)
        let entry = TimeZoneSearch.entry(for: app.timeZoneIdentifier)
        let isEditing = editingApplication?.id == app.id
        return Button {
            actions.launch(app)
        } label: {
            VStack(spacing: 2) {
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
                    .overlay(alignment: .topLeading) {
                        if app.automaticallyManageLaunches {
                            Image(systemName: "bolt.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.white, Color.accentColor)
                                .offset(x: -3, y: -3)
                        }
                    }
                Text(app.displayName)
                    .font(.system(size: 10))
                    .lineLimit(1)
                Text(entry.title)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isEditing ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(app.displayName) · \(entry.title) \(entry.offsetLabel()) · \(status.menuLabel)")
        .contextMenu {
            Button(status == .notRunning ? "按「\(entry.title)」时区打开" : "按「\(entry.title)」时区重新打开") {
                actions.launch(app)
            }
            Button("更改时区…") { expansion = .applicationTimeZone(app.id) }
            Toggle("自动接管", isOn: Binding(
                get: { app.automaticallyManageLaunches },
                set: { _ in settings.toggleAutomaticLaunchManagement(for: app.id) }
            ))
            Divider()
            Button("在访达中显示") { actions.reveal(app) }
            Button("移出白名单", role: .destructive) { settings.removeApplication(id: app.id) }
        }
    }

    private var addApplicationCell: some View {
        Button(action: actions.addApplications) {
            VStack(spacing: 2) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    )
                Text("添加")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(" ")
                    .font(.system(size: 9))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("添加应用到白名单…")
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("详细设置…", action: actions.openSettings)
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

private struct PillButton: View {
    let title: String
    let symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
