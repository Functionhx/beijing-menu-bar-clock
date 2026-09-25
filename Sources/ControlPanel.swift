import AppKit
import SwiftUI

struct ControlPanelActions {
    let openSettings: () -> Void
    let launch: (ManagedTimeZoneApp) -> Void
    let reveal: (ManagedTimeZoneApp) -> Void
    let addApplications: () -> Void
    let chooseCustomSound: () -> Void
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

/// Drop-down panel under the status item. The window itself is fully transparent: every card is its own
/// piece of Liquid Glass floating over the desktop, like Control Center on iOS 26.
@MainActor
final class ControlPanelController: NSObject, NSWindowDelegate {
    /// Transparent margin around the cards so glass shadows and the appear animation aren't clipped.
    static let outerPadding: CGFloat = 14

    private let panel: ControlPanelWindow
    private let hostingView: ResizingHostingView<ControlPanelView>
    private let settings: ClockSettings
    private let actions: ControlPanelActions
    private var outsideClickMonitor: Any?
    private var lastClosed = Date.distantPast
    private var session = 0
    private var resizeGeneration = 0
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
        // Each glass card casts its own soft shadow; a window shadow would outline the transparent margin.
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        hostingView.onIntrinsicSizeChange = { [weak self] in self?.scheduleResize() }
    }

    /// True right after the panel closed, so the same status item click that dismissed it doesn't reopen it.
    var justClosed: Bool { Date().timeIntervalSince(lastClosed) < 0.25 }

    /// Shows the panel under the status item, optionally with a section already expanded (e.g. time zone search).
    func show(below button: NSStatusBarButton, expanding expansion: ControlPanelView.Expansion? = nil) {
        guard let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }

        // A fresh view identity each time, so searches start collapsed and the appear animation replays.
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
        let margin = Self.outerPadding
        let x = min(max(anchor.midX - size.width / 2, visible.minX - margin + 8), visible.maxX - size.width + margin - 8)
        // The first card sits 6pt under the menu bar; the transparent margin may overlap the menu bar.
        let top = min(anchor.minY, visible.maxY) - 6 + margin

        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
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

    /// Grows immediately, but shrinks only after the collapse spring has settled so the glass isn't clipped mid-morph.
    private func scheduleResize() {
        guard isOpen else { return }
        resizeGeneration += 1
        let generation = resizeGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isOpen, generation == self.resizeGeneration else { return }
            let height = self.hostingView.fittingSize.height
            let delay = height < self.panel.frame.height ? 0.4 : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isOpen, generation == self.resizeGeneration else { return }
                let height = self.hostingView.fittingSize.height
                var frame = self.panel.frame
                guard abs(frame.height - height) > 0.5 else { return }
                // Keep the top edge pinned under the menu bar.
                frame.origin.y = frame.maxY - height
                frame.size.height = height
                self.panel.setFrame(frame, display: true)
            }
        }
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
        ControlPanelContent(
            settings: settings,
            actions: actions,
            expansion: initialExpansion,
            tab: PanelTab.initial(for: initialExpansion)
        )
        .id(session)
    }
}

/// Top-level sections of the panel, shown one at a time under the clock like the ultra edition.
enum PanelTab: String, CaseIterable, Identifiable {
    case calendar, clock, applications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar: return "日历"
        case .clock: return "时钟"
        case .applications: return "应用"
        }
    }

    var symbol: String {
        switch self {
        case .calendar: return "calendar"
        case .clock: return "clock.fill"
        case .applications: return "app.badge.clock.fill"
        }
    }

    /// The panel always opens on the calendar unless it was opened to edit something specific.
    static func initial(for expansion: ControlPanelView.Expansion?) -> PanelTab {
        switch expansion {
        case .clockTimeZone: return .clock
        case .applicationTimeZone: return .applications
        case nil: return .calendar
        }
    }
}

// MARK: - Layout constants

enum Metrics {
    static let width: CGFloat = 340
    static let cardRadius: CGFloat = 26
    static let cardPadding: CGFloat = 14
    /// Inner shapes stay concentric with the card: outer radius minus padding.
    static let innerRadius: CGFloat = cardRadius - cardPadding
    static let spacing: CGFloat = 10
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)
}

private struct ControlPanelContent: View {
    @ObservedObject var settings: ClockSettings
    @ObservedObject var loginItem = LoginItem.shared
    let actions: ControlPanelActions
    @State var expansion: ControlPanelView.Expansion?
    @State var tab: PanelTab
    @State private var appeared = false
    @Namespace private var glassNamespace
    @Namespace private var tabNamespace

    private let chinese = Locale(identifier: "zh_CN")

    var body: some View {
        // Container spacing is smaller than the gaps between cards, so cards stay separate at rest and
        // only melt together when a morphing element passes between them.
        VStack(spacing: Metrics.spacing) {
            GlassEffectContainer(spacing: 6) {
                VStack(spacing: Metrics.spacing) {
                    hero
                    tabBar
                }
            }
            tabContent
                .id(tab)
            GlassEffectContainer(spacing: 6) {
                footer
            }
        }
        .frame(width: Metrics.width)
        .padding(ControlPanelController.outerPadding)
        .scaleEffect(appeared ? 1 : 0.92, anchor: .top)
        .opacity(appeared ? 1 : 0)
        .blur(radius: appeared ? 0 : 6)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { appeared = true }
            loginItem.refresh()
        }
    }

    /// Each tab gets a fresh glass container. Views inserted into an existing GlassEffectContainer after it first
    /// rendered stay visible but never receive clicks (macOS 26), so switching tabs rebuilds the container.
    private var tabContent: some View {
        GlassEffectContainer(spacing: 6) {
            VStack(spacing: Metrics.spacing) {
                switch tab {
                case .calendar:
                    CalendarCard(settings: settings, namespace: glassNamespace)
                case .clock:
                    displayToggles
                    launchAtLoginCard
                    timeZoneCard
                    announcementCard
                case .applications:
                    applicationsCard
                }
            }
        }
    }

    // MARK: Hero clock

    private var hero: some View {
        // Tick on whole seconds, matching the menu bar clock.
        let start = Date(timeIntervalSinceReferenceDate: Date.timeIntervalSinceReferenceDate.rounded(.down))
        return TimelineView(.periodic(from: start, by: 1)) { context in
            let date = context.date
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: settings.useSystemTimeZone ? "location.fill" : "globe.asia.australia.fill")
                        .symbolRenderingMode(.hierarchical)
                        .contentTransition(.symbolEffect(.replace))
                    Text(heroZoneTitle)
                    Spacer(minLength: 8)
                    Text(currentEntry.offsetLabel(at: date))
                        .monospacedDigit()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(format(date, "HH:mm"))
                        .font(.system(size: 58, weight: .semibold, design: .rounded))
                    Text(format(date, ":ss"))
                        .font(.system(size: 30, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: false))
                .animation(.snappy(duration: 0.3), value: date)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                Text("\(format(date, "yyyy年M月d日 EEEE")) · \(lunarLabel(date))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: Metrics.cardRadius + 4))
            .glassEffectID("hero", in: glassNamespace)
        }
    }

    /// "农历八月十五" plus " · 秋分" on the day of a solar term, by the clock's calendar day.
    private func lunarLabel(_ date: Date) -> String {
        let parts = CalendarCard.calendar(in: settings.effectiveTimeZone).dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 2000, month = parts.month ?? 1, day = parts.day ?? 1
        let lunar = LunarCalendar.lunarDate(year: year, month: month, day: day)
        let term = SolarTerms.termName(year: year, month: month, day: day).map { " · \($0)" } ?? ""
        return "农历\(lunar.monthName)\(lunar.dayName)\(term)"
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(PanelTab.allCases) { item in
                let isSelected = item == tab
                Button {
                    withAnimation(Metrics.spring) {
                        tab = item
                        expansion = nil
                    }
                } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.accentColor.gradient)
                                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "selection", in: tabNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .glassEffectID("tabs", in: glassNamespace)
    }

    // MARK: Launch at login

    private var launchAtLoginCard: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(Metrics.spring) { loginItem.setEnabled(!loginItem.isEnabled) }
            } label: {
                StateCircle(symbol: "power", isOn: loginItem.isEnabled)
            }
            .buttonStyle(.plain)
            .help(loginItem.isEnabled ? "登录 Mac 时不再自动打开" : "登录 Mac 时自动打开")

            CardLabel(title: "开机启动", subtitle: loginItem.lastError ?? loginItem.subtitle)
            Spacer(minLength: 4)

            if loginItem.status == .requiresApproval {
                Button("去批准", action: loginItem.openSystemSettings)
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
        }
        .card(id: "login", in: glassNamespace)
    }

    private var currentEntry: TimeZoneEntry {
        TimeZoneSearch.entry(for: settings.effectiveTimeZone.identifier)
    }

    private var heroZoneTitle: String {
        settings.useSystemTimeZone ? "跟随系统 · \(currentEntry.title)" : currentEntry.title
    }

    // MARK: Display toggles

    private var displayToggles: some View {
        let toggles: [(title: String, symbol: String, binding: Binding<Bool>)] = [
            ("日期", "calendar", $settings.showDate),
            ("星期", "calendar.day.timeline.left", $settings.showWeekday),
            ("秒钟", "stopwatch.fill", $settings.showSeconds),
            ("闪动分隔符", "sparkles", $settings.flashSeparators)
        ]
        let states = toggles.map { $0.binding.wrappedValue }
        return HStack(spacing: 8) {
            ForEach(Array(toggles.enumerated()), id: \.offset) { index, toggle in
                GlassToggleTile(
                    title: toggle.title,
                    symbol: toggle.symbol,
                    isOn: toggle.binding.wrappedValue,
                    unionID: Self.unionID(for: index, states: states),
                    namespace: glassNamespace
                )
            }
        }
        // Hit targets live in a separate row above the glass. When tiles fuse through glassEffectUnion the
        // merged glass is drawn by the last member and swallows clicks meant for the earlier tiles, so
        // per-tile buttons stop working (e.g. 日期 and 星期 while 秒钟 is also on).
        .overlay {
            HStack(spacing: 8) {
                ForEach(Array(toggles.enumerated()), id: \.offset) { _, toggle in
                    Button {
                        withAnimation(Metrics.spring) { toggle.binding.wrappedValue.toggle() }
                    } label: {
                        Color.clear
                            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(toggle.title)
                    .accessibilityValue(toggle.binding.wrappedValue ? "开" : "关")
                    .help("\(toggle.binding.wrappedValue ? "隐藏" : "显示")\(toggle.title)")
                }
            }
        }
    }

    /// Neighbouring tiles that are both on share a union id, so their tinted glass fuses into one bar
    /// and splits apart again when one in the middle is switched off.
    private static func unionID(for index: Int, states: [Bool]) -> String {
        guard states[index] else { return "off-\(index)" }
        var start = index
        while start > 0 && states[start - 1] { start -= 1 }
        return "on-\(start)"
    }

    // MARK: Time zone

    private var isSearchingClockZone: Bool {
        if case .clockTimeZone = expansion { return true }
        return false
    }

    private var timeZoneCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(Metrics.spring) { settings.useSystemTimeZone.toggle() }
                } label: {
                    StateCircle(symbol: "location.fill", isOn: settings.useSystemTimeZone)
                }
                .buttonStyle(.plain)
                .help(settings.useSystemTimeZone ? "改为自选时区" : "跟随系统时区")

                CardLabel(
                    title: "时区",
                    subtitle: settings.useSystemTimeZone
                        ? "跟随系统 · \(settings.shortTimeZoneName(settings.effectiveTimeZone))"
                        : "\(currentEntry.title) · \(settings.shortTimeZoneName(settings.effectiveTimeZone))"
                )

                Spacer(minLength: 4)

                Button {
                    withAnimation(Metrics.spring) {
                        expansion = isSearchingClockZone ? nil : .clockTimeZone()
                    }
                } label: {
                    Label(isSearchingClockZone ? "完成" : "搜索", systemImage: isSearchingClockZone ? "checkmark" : "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }

            if case let .clockTimeZone(query) = expansion {
                TimeZoneSearchView(
                    current: settings.useSystemTimeZone ? nil : settings.timeZoneIdentifier,
                    recents: settings.recentTimeZoneIdentifiers,
                    suggestions: settings.quickTimeZoneChoices,
                    initialQuery: query,
                    onSelect: { identifier in
                        withAnimation(Metrics.spring) {
                            settings.selectClockTimeZone(identifier)
                            expansion = nil
                        }
                    },
                    onCancel: { withAnimation(Metrics.spring) { expansion = nil } }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .card(id: "timezone", in: glassNamespace)
    }

    // MARK: Announcement

    private var announcementCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(Metrics.spring) { settings.announceTime.toggle() }
                } label: {
                    StateCircle(
                        symbol: settings.announceTime ? "speaker.wave.2.fill" : "speaker.slash.fill",
                        isOn: settings.announceTime
                    )
                }
                .buttonStyle(.plain)
                .help(settings.announceTime ? "关闭语音报时" : "开启语音报时")

                CardLabel(title: "语音报时", subtitle: settings.announceTime ? settings.announceInterval : "关")
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
                    Label(soundLabel, systemImage: "bell.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .fixedSize()
                .disabled(!settings.announceTime)
                .help("报时声音：\(soundLabel)")
            }

            LiquidSegmentedControl(
                choices: settings.announceIntervalChoices,
                selection: $settings.announceInterval
            )
            .disabled(!settings.announceTime)
            .opacity(settings.announceTime ? 1 : 0.5)
        }
        .card(id: "announcement", in: glassNamespace)
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

    private var applicationsCard: some View {
        let _ = settings.applicationStatusRevision
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "app.badge.clock.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text("按指定时区打开")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("自动接管")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Toggle("自动接管", isOn: Binding(
                    get: { settings.allApplicationsAutomaticallyManaged },
                    set: { value in withAnimation(Metrics.spring) { settings.setAutomaticLaunchManagementForAll(value) } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(settings.managedTimeZoneApps.isEmpty)
                .help("开启后，从 Dock 或访达打开的白名单应用也会被自动切换到指定时区")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 4)], spacing: 10) {
                ForEach(settings.managedTimeZoneApps) { app in
                    applicationCell(app)
                }
                addApplicationCell
            }

            if let app = editingApplication {
                VStack(alignment: .leading, spacing: 8) {
                    Text("为「\(app.displayName)」选择时区")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TimeZoneSearchView(
                        current: app.timeZoneIdentifier,
                        recents: settings.recentTimeZoneIdentifiers,
                        suggestions: settings.quickTimeZoneChoices,
                        listHeight: 168,
                        onSelect: { identifier in
                            withAnimation(Metrics.spring) {
                                settings.setTimeZone(identifier, forApplication: app.id)
                                expansion = nil
                            }
                        },
                        onCancel: { withAnimation(Metrics.spring) { expansion = nil } }
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text(settings.managedTimeZoneApps.isEmpty ? "添加应用后，点按即可按指定时区打开" : "点按打开 · 右键更改时区或自动接管")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .card(id: "applications", in: glassNamespace)
    }

    private func applicationCell(_ app: ManagedTimeZoneApp) -> some View {
        let status = settings.launchStatus(for: app)
        let entry = TimeZoneSearch.entry(for: app.timeZoneIdentifier)
        let isEditing = editingApplication?.id == app.id
        return Button {
            actions.launch(app)
        } label: {
            VStack(spacing: 3) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.applicationURL.path))
                    .resizable()
                    .frame(width: 38, height: 38)
                    .overlay(alignment: .bottomTrailing) {
                        if let color = statusColor(status) {
                            Circle()
                                .fill(color.gradient)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                                .offset(x: 2, y: 2)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if app.automaticallyManageLaunches {
                            Image(systemName: "bolt.circle.fill")
                                .font(.system(size: 13))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .offset(x: -4, y: -4)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                Text(app.displayName)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                Text(entry.title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if isEditing {
                    RoundedRectangle(cornerRadius: Metrics.innerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.2))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Metrics.innerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(app.displayName) · \(entry.title) \(entry.offsetLabel()) · \(status.menuLabel)")
        .contextMenu {
            Button(status == .notRunning ? "按「\(entry.title)」时区打开" : "按「\(entry.title)」时区重新打开") {
                actions.launch(app)
            }
            Button("更改时区…") { withAnimation(Metrics.spring) { expansion = .applicationTimeZone(app.id) } }
            Toggle("自动接管", isOn: Binding(
                get: { app.automaticallyManageLaunches },
                set: { _ in withAnimation(Metrics.spring) { settings.toggleAutomaticLaunchManagement(for: app.id) } }
            ))
            Divider()
            Button("在访达中显示") { actions.reveal(app) }
            Button("移出白名单", role: .destructive) { settings.removeApplication(id: app.id) }
        }
    }

    private var addApplicationCell: some View {
        Button(action: actions.addApplications) {
            VStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    )
                Text("添加")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(" ")
                    .font(.system(size: 9.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("添加应用到白名单…")
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: actions.openSettings) {
                Label("详细设置", systemImage: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .glassEffectID("settings", in: glassNamespace)

            Spacer()

            Button(action: actions.checkForUpdates) {
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .help("检查更新…")
            .glassEffectID("updates", in: glassNamespace)

            Button(action: actions.quit) {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .bold))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .help("退出北京时间")
            .glassEffectID("quit", in: glassNamespace)
        }
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

// MARK: - Components

/// A glass tile that turns into tinted glass when on. Adjacent "on" tiles fuse through `glassEffectUnion`.
private struct GlassToggleTile: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let unionID: String
    let namespace: Namespace.ID

    var body: some View {
        // Display only; ControlPanelContent.displayToggles overlays the buttons (see the note there).
        // Keeping Buttons out of the union also avoids a macOS 26 SDK hang: a glassEffectUnion containing a
        // Button inside a GlassEffectContainer loops forever building the key view loop when the panel becomes key.
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce, value: isOn)
                .frame(height: 22)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isOn ? Color.white : Color.primary)
        .frame(maxWidth: .infinity)
        .frame(height: 68)
        .glassEffect(
            isOn ? .regular.tint(Color.accentColor.opacity(0.9)).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: 22)
        )
        .glassEffectUnion(id: unionID, namespace: namespace)
        .glassEffectID("toggle-\(title)", in: namespace)
    }
}

/// Solid state indicator used inside glass cards (glass on glass would muddy the card).
struct StateCircle: View {
    let symbol: String
    let isOn: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 36, height: 36)
            .background {
                Circle()
                    .fill(isOn ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary))
            }
            .contentShape(Circle())
    }
}

/// Capsule segmented control whose selection pill slides between segments with a spring.
private struct LiquidSegmentedControl: View {
    let choices: [String]
    @Binding var selection: String
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(choices, id: \.self) { choice in
                let isSelected = choice == selection
                Button {
                    withAnimation(Metrics.spring) { selection = choice }
                } label: {
                    Text(choice)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.accentColor.gradient)
                                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(.quaternary))
    }
}

struct CardLabel: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
    }
}

extension View {
    /// A floating Liquid Glass card. Its size animates when content expands, so the glass itself morphs.
    func card(id: String, in namespace: Namespace.ID) -> some View {
        padding(Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerShape(.rect(cornerRadius: Metrics.cardRadius))
            .glassEffect(.regular, in: .rect(cornerRadius: Metrics.cardRadius))
            .glassEffectID(id, in: namespace)
    }
}
