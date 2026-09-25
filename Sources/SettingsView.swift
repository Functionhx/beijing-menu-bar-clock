import AppKit
import SwiftUI

/// Pages of the 详细设置 window.
enum SettingsPage: String, CaseIterable, Identifiable {
    case display, timeZone, applications, announcement, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .display: return "菜单栏显示"
        case .timeZone: return "时区"
        case .applications: return "应用时区白名单"
        case .announcement: return "语音报时"
        case .about: return "关于与更新"
        }
    }

    var symbol: String {
        switch self {
        case .display: return "menubar.rectangle"
        case .timeZone: return "globe.asia.australia.fill"
        case .applications: return "app.badge.clock.fill"
        case .announcement: return "speaker.wave.2.fill"
        case .about: return "arrow.trianglehead.2.clockwise"
        }
    }

    var tint: Color {
        switch self {
        case .display: return .blue
        case .timeZone: return .teal
        case .applications: return .indigo
        case .announcement: return .orange
        case .about: return .gray
        }
    }

    var summary: String {
        switch self {
        case .display: return "决定菜单栏里的时钟显示哪些内容。"
        case .timeZone: return "菜单栏时钟使用的时区，不影响系统时区。"
        case .applications: return "让指定应用以独立时区启动，例如微信按北京时间显示。"
        case .announcement: return "按固定间隔用中文播报当前时间。"
        case .about: return "版本信息与自动更新。"
        }
    }
}

/// Shared selection between the sidebar and the detail page.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var page: SettingsPage?

    init(page: SettingsPage) {
        self.page = page
    }
}

/// 详细设置 window: an AppKit split view so macOS 26 draws the floating Liquid Glass sidebar,
/// with SwiftUI for the sidebar list and the pages, and a prominent glass 完成 button in the toolbar.
@MainActor
final class SettingsWindowController: NSObject, NSToolbarDelegate {
    private static let doneItem = NSToolbarItem.Identifier("done")

    let window: NSWindow
    private let navigation: SettingsNavigation

    init(settings: ClockSettings, initialPage: SettingsPage = .display, onCheckForUpdates: @escaping () -> Void) {
        navigation = SettingsNavigation(page: initialPage)

        let sidebar = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: SettingsSidebar(navigation: navigation)))
        sidebar.minimumThickness = 190
        sidebar.maximumThickness = 260
        sidebar.canCollapse = false
        sidebar.allowsFullHeightLayout = true
        let detail = NSSplitViewItem(viewController: NSHostingController(rootView: SettingsView(
            settings: settings,
            navigation: navigation,
            onCheckForUpdates: onCheckForUpdates
        )))
        detail.minimumThickness = 500
        let split = NSSplitViewController()
        split.splitViewItems = [sidebar, detail]

        window = NSWindow(contentViewController: split)
        super.init()

        window.title = "详细设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.setContentSize(NSSize(width: 820, height: 600))
        window.contentMinSize = NSSize(width: 720, height: 480)
        window.center()
    }

    func show(page: SettingsPage? = nil) {
        if let page { navigation.page = page }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func done() {
        window.close()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.doneItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.doneItem]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard identifier == Self.doneItem else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.title = "完成"
        item.label = "完成"
        item.style = .prominent
        item.target = self
        item.action = #selector(done)
        return item
    }
}

private struct SettingsSidebar: View {
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        List(SettingsPage.allCases, selection: $navigation.page) { page in
            Label {
                Text(page.title)
            } icon: {
                Image(systemName: page.symbol)
                    .foregroundStyle(page.tint)
                    .symbolRenderingMode(.hierarchical)
            }
            .tag(page)
        }
        .listStyle(.sidebar)
    }
}

struct SettingsView: View {
    typealias Page = SettingsPage

    @ObservedObject var settings: ClockSettings
    @ObservedObject var navigation: SettingsNavigation
    let onCheckForUpdates: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let current = navigation.page ?? .display
                PageHeader(page: current)
                content(for: current)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    @ViewBuilder
    private func content(for page: Page) -> some View {
        switch page {
        case .display: displayPage
        case .timeZone: timeZonePage
        case .applications: applicationsPage
        case .announcement: announcementPage
        case .about: aboutPage
        }
    }

    // MARK: Display

    private var displayPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            MenuBarPreview(settings: settings)

            GlassSection("日期") {
                SwitchRow("显示日期", isOn: $settings.showDate)
                Divider()
                SwitchRow("显示星期", isOn: $settings.showWeekday)
            }

            GlassSection("时间") {
                SwitchRow("在时间中显示秒钟", isOn: $settings.showSeconds)
                Divider()
                SwitchRow("闪动时间分隔符", isOn: $settings.flashSeparators)
            }
        }
    }

    // MARK: Time zone

    private var timeZonePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            GlassSection("时钟时区") {
                SwitchRow("使用系统时区", isOn: $settings.useSystemTimeZone)
                Divider()
                HStack {
                    Text("自选时区")
                    Spacer()
                    TimeZoneSearchButton(
                        settings: settings,
                        identifier: settings.timeZoneIdentifier,
                        onSelect: settings.selectClockTimeZone
                    )
                    .frame(width: 300)
                }
                .disabled(settings.useSystemTimeZone)
            }

            if !settings.recentTimeZoneIdentifiers.isEmpty {
                GlassSection("最近使用") {
                    GlassEffectContainer(spacing: 8) {
                        FlowRow(spacing: 8) {
                            ForEach(settings.recentTimeZoneIdentifiers, id: \.self) { identifier in
                                let entry = TimeZoneSearch.entry(for: identifier)
                                let isCurrent = !settings.useSystemTimeZone && identifier == settings.timeZoneIdentifier
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        settings.selectClockTimeZone(identifier)
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Text(entry.title).fontWeight(.semibold)
                                        Text(entry.offsetLabel())
                                            .foregroundStyle(isCurrent ? .white.opacity(0.85) : .secondary)
                                            .monospacedDigit()
                                    }
                                }
                                .buttonStyle(GlassChipStyle(isOn: isCurrent))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Applications

    private var applicationsPage: some View {
        let _ = settings.applicationStatusRevision
        return VStack(alignment: .leading, spacing: 20) {
            GlassSection("自动接管") {
                Toggle(isOn: Binding(
                    get: { settings.allApplicationsAutomaticallyManaged },
                    set: { settings.setAutomaticLaunchManagementForAll($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("全局自动接管")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("从 Dock 或访达正常打开的白名单应用，会被自动重开并切换到指定时区。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .disabled(settings.managedTimeZoneApps.isEmpty)
            }

            GlassSection("应用") {
                if settings.managedTimeZoneApps.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.largeTitle)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                        Text("尚未添加应用")
                            .font(.headline)
                        Text("添加后，点按菜单栏面板里的图标即可按独立时区打开。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    ForEach(settings.managedTimeZoneApps) { app in
                        applicationRow(app)
                        if app.id != settings.managedTimeZoneApps.last?.id {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
            } trailing: {
                Button {
                    settings.chooseApplications()
                } label: {
                    Label("添加应用…", systemImage: "plus")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
    }

    private func applicationRow(_ app: ManagedTimeZoneApp) -> some View {
        let status = settings.launchStatus(for: app)
        return HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.applicationURL.path))
                .resizable()
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Label(status.label, systemImage: status.symbolName)
                    .font(.caption)
                    .foregroundStyle(statusColor(status))
                    .lineLimit(1)
            }
            .frame(width: 140, alignment: .leading)

            TimeZoneSearchButton(
                settings: settings,
                identifier: app.timeZoneIdentifier,
                onSelect: { settings.setTimeZone($0, forApplication: app.id) }
            )
            .frame(maxWidth: .infinity)

            Toggle("自动", isOn: Binding(
                get: { app.automaticallyManageLaunches },
                set: { _ in settings.toggleAutomaticLaunchManagement(for: app.id) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("开启后，从 Dock 或访达启动也会自动重开一次并注入时区")

            Button(status == .notRunning ? "打开" : "重启") {
                settings.launch(app)
            }
            .buttonStyle(.glass)
            .controlSize(.small)

            Menu {
                Button("在访达中显示") { settings.reveal(app) }
                Divider()
                Button("移出白名单", role: .destructive) {
                    settings.removeApplication(id: app.id)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .fixedSize()
        }
    }

    // MARK: Announcement

    private var announcementPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            GlassSection("报时") {
                SwitchRow("语音报时", isOn: $settings.announceTime)
                Divider()
                HStack {
                    Text("时间间隔")
                    Spacer()
                    Picker("时间间隔", selection: $settings.announceInterval) {
                        ForEach(settings.announceIntervalChoices, id: \.self) { interval in
                            Text(interval).tag(interval)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }
                .disabled(!settings.announceTime)
            }

            GlassSection("声音") {
                HStack {
                    Text("提示音")
                    Spacer()
                    Picker("提示音", selection: $settings.soundName) {
                        ForEach(settings.soundChoices, id: \.self) { sound in
                            Text(sound).tag(sound)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    .onChange(of: settings.soundName) { _, newValue in
                        if newValue == "自定义…" && settings.customSoundPath.isEmpty {
                            settings.chooseCustomSound()
                        }
                    }
                }
                if settings.soundName == "自定义…" {
                    Divider()
                    HStack {
                        Text(settings.customSoundPath.isEmpty ? "尚未选择音频" : URL(fileURLWithPath: settings.customSoundPath).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("选择音频…") { settings.chooseCustomSound() }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                    }
                }
            }
            .disabled(!settings.announceTime)
        }
    }

    // MARK: About

    private var aboutPage: some View {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "开发版"
        let build = info["CFBundleVersion"] as? String ?? "-"
        let name = info["CFBundleDisplayName"] as? String ?? "北京时间"
        return VStack(alignment: .leading, spacing: 20) {
            GlassSection("版本") {
                HStack(spacing: 14) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .glassEffect(.regular.tint(.accentColor), in: .rect(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name).font(.title3.weight(.semibold))
                        Text("版本 \(version)（\(build)）").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("检查更新…", action: onCheckForUpdates)
                        .buttonStyle(.glassProminent)
                }
            }
            Text("启用自动更新后，每天会向 GitHub 检查一次新版本，不收集任何数据。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func statusColor(_ status: ManagedAppLaunchStatus) -> Color {
        switch status {
        case .applied: return .green
        case .notApplied, .mismatched: return .orange
        case .notRunning, .unavailable: return .secondary
        }
    }
}

// MARK: - Components

private struct PageHeader: View {
    let page: SettingsPage

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: page.symbol)
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .glassEffect(.regular.tint(page.tint), in: .circle)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 3) {
                Text(page.title)
                    .font(.system(size: 24, weight: .bold))
                Text(page.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }
}

/// Title on the left, switch on the right, like System Settings.
private struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
    }
}

/// A titled group of rows on a Liquid Glass card.
private struct GlassSection<Content: View, Trailing: View>: View {
    let title: String
    let content: Content
    let trailing: Trailing

    init(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                trailing
            }
            .padding(.horizontal, 6)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
        }
    }
}

private extension GlassSection where Trailing == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, content: content, trailing: { EmptyView() })
    }
}

/// Live preview of the menu bar text on a glass "menu bar" strip.
private struct MenuBarPreview: View {
    @ObservedObject var settings: ClockSettings

    var body: some View {
        let start = Date(timeIntervalSinceReferenceDate: Date.timeIntervalSinceReferenceDate.rounded(.down))
        TimelineView(.periodic(from: start, by: 1)) { context in
            HStack(spacing: 14) {
                Image(systemName: "apple.logo")
                Spacer()
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text(previewText(context.date))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: context.date)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                Image(systemName: "switch.2")
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(height: 38)
            .glassEffect(.regular, in: .capsule)
        }
        .accessibilityLabel("菜单栏预览")
    }

    private func previewText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = settings.effectiveTimeZone
        var parts: [String] = []
        if settings.showDate {
            formatter.dateFormat = "M月d日"
            parts.append(formatter.string(from: date))
        }
        if settings.showWeekday {
            formatter.dateFormat = "EEE"
            parts.append(formatter.string(from: date))
        }
        formatter.dateFormat = settings.showSeconds ? "HH:mm:ss" : "HH:mm"
        parts.append(formatter.string(from: date))
        return parts.joined(separator: " ")
    }
}

/// Capsule chip: clear glass when off, tinted glass when it is the current value.
private struct GlassChipStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(isOn ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

/// Simple wrapping row layout for chips.
private struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Button showing the chosen zone; opens a searchable list in a popover.
private struct TimeZoneSearchButton: View {
    @ObservedObject var settings: ClockSettings
    let identifier: String
    let onSelect: (String) -> Void
    @State private var isSearching = false

    var body: some View {
        let entry = TimeZoneSearch.entry(for: identifier)
        Button {
            isSearching.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(entry.title)
                    .fontWeight(.medium)
                Text("\(entry.localizedName) · \(entry.offsetLabel())")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .help(identifier)
        .popover(isPresented: $isSearching, arrowEdge: .bottom) {
            TimeZoneSearchView(
                current: identifier,
                recents: settings.recentTimeZoneIdentifiers,
                suggestions: settings.quickTimeZoneChoices,
                listHeight: 280,
                onSelect: { selected in
                    onSelect(selected)
                    isSearching = false
                },
                onCancel: { isSearching = false }
            )
            .padding(10)
            .frame(width: 340)
        }
    }
}
