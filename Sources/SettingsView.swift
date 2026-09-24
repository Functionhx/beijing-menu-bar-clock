import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: ClockSettings
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    sectionTitle("时区")
                    settingsCard {
                        Toggle("使用系统时区", isOn: $settings.useSystemTimeZone)
                        Divider()
                        HStack {
                            Text("自选时区")
                            Spacer()
                            Picker("", selection: $settings.timeZoneIdentifier) {
                                ForEach(settings.timeZoneChoices, id: \.self) { identifier in
                                    Text(settings.timeZoneLabel(identifier)).tag(identifier)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 290)
                        }
                        .disabled(settings.useSystemTimeZone)
                    }

                    sectionTitle("应用时区白名单")
                    settingsCard {
                        HStack {
                            Label("全局自动接管", systemImage: "bolt.fill")
                            Spacer()
                            Button(settings.allApplicationsAutomaticallyManaged ? "全部关闭" : "全部开启") {
                                settings.setAutomaticLaunchManagementForAll(!settings.allApplicationsAutomaticallyManaged)
                            }
                            .disabled(settings.managedTimeZoneApps.isEmpty)
                        }

                        Divider()

                        if settings.managedTimeZoneApps.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "clock.badge.questionmark")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("尚未添加应用")
                                    .font(.headline)
                                Text("添加后，从北京时间菜单启动它们即可使用独立时区。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        } else {
                            ForEach($settings.managedTimeZoneApps) { $app in
                                applicationRow(app: $app)
                                if app.id != settings.managedTimeZoneApps.last?.id {
                                    Divider().padding(.leading, 42)
                                }
                            }
                        }

                        Divider()
                        HStack {
                            Button {
                                settings.chooseApplications()
                            } label: {
                                Label("添加应用…", systemImage: "plus")
                            }
                            Spacer()
                            Text("可直接从 Dock 或访达打开，工具会自动接管")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    sectionTitle("日期")
                    settingsCard {
                        Toggle("显示日期", isOn: $settings.showDate)
                        Divider()
                        Toggle("显示星期", isOn: $settings.showWeekday)
                    }

                    sectionTitle("时间")
                    settingsCard {
                        Toggle("闪动时间分隔符", isOn: $settings.flashSeparators)
                        Divider()
                        Toggle("在时间中显示秒钟", isOn: $settings.showSeconds)
                    }

                    settingsCard {
                        Toggle("语音报时", isOn: $settings.announceTime)
                        Divider()

                        HStack {
                            Text("时间间隔")
                            Spacer()
                            Picker("", selection: $settings.announceInterval) {
                                Text("每小时").tag("每小时")
                                Text("每半小时").tag("每半小时")
                                Text("每刻钟").tag("每刻钟")
                            }
                            .labelsHidden()
                            .frame(width: 130)
                        }
                        .disabled(!settings.announceTime)

                        Divider()

                        HStack {
                            Text("声音")
                            Spacer()
                            Picker("", selection: $settings.soundName) {
                                ForEach(settings.soundChoices, id: \.self) { sound in
                                    Text(sound).tag(sound)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 130)
                            .onChange(of: settings.soundName) { _, newValue in
                                if newValue == "自定义…" && settings.customSoundPath.isEmpty {
                                    settings.chooseCustomSound()
                                }
                            }
                        }
                        .disabled(!settings.announceTime)

                        if settings.announceTime && settings.soundName == "自定义…" {
                            HStack {
                                Text(settings.customSoundPath.isEmpty ? "尚未选择音频" : URL(fileURLWithPath: settings.customSoundPath).lastPathComponent)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Button("自定义声音…") { settings.chooseCustomSound() }
                            }
                        }
                    }
                }
                .padding(24)
            }

            Divider()
            HStack {
                Spacer()
                Button("完成", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)
            .background(.regularMaterial)
        }
        .frame(width: 730, height: 760)
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12) {
            content()
        }
        .padding(16)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .padding(.leading, 2)
            .padding(.bottom, -12)
    }

    @ViewBuilder
    private func applicationRow(app: Binding<ManagedTimeZoneApp>) -> some View {
        let value = app.wrappedValue
        let status = settings.launchStatus(for: value)
        let _ = settings.applicationStatusRevision
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: value.applicationURL.path))
                .resizable()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(value.displayName)
                    .lineLimit(1)
                Label(status.label, systemImage: status.symbolName)
                    .font(.caption)
                    .foregroundStyle(statusColor(status))
                    .lineLimit(1)
            }
            .frame(width: 155, alignment: .leading)

            Picker("时区", selection: app.timeZoneIdentifier) {
                ForEach(settings.timeZoneChoices, id: \.self) { identifier in
                    Text(settings.timeZoneLabel(identifier)).tag(identifier)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button(status == .notRunning ? "打开" : "重启") {
                settings.launch(value)
            }
            .frame(width: 52)

            Button(value.automaticallyManageLaunches ? "自动：开" : "自动：关") {
                settings.toggleAutomaticLaunchManagement(for: value.id)
            }
            .controlSize(.small)
            .foregroundStyle(value.automaticallyManageLaunches ? .blue : .secondary)
            .help("开启后，从 Dock 或访达启动也会自动重开一次并注入时区")

            Menu {
                Button("在访达中显示") { settings.reveal(value) }
                Divider()
                Button("移出白名单", role: .destructive) {
                    settings.removeApplication(id: value.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
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
