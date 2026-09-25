import AppKit
import SwiftUI

/// Rounded card used by every section of the 详细设置 window.
struct SettingsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 12) {
            content
        }
        .padding(16)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SettingsSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .padding(.leading, 2)
            .padding(.bottom, -12)
    }
}

/// Launch at login and the global shortcut, at the top of the 时钟 tab.
struct GeneralSettingsCards: View {
    @ObservedObject var ultra: UltraSettings
    @ObservedObject var loginItem = LoginItem.shared
    @ObservedObject var hotKey = GlobalHotKey.shared

    var body: some View {
        SettingsSectionTitle(title: "通用")
        SettingsCard {
            HStack {
                Toggle("登录时打开", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
                Spacer()
                if loginItem.status == .requiresApproval {
                    Button("在系统设置中批准…") { loginItem.openSystemSettings() }
                }
            }
            if let error = loginItem.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Toggle("全局快捷键打开面板", isOn: $ultra.hotKey.isEnabled)
                Spacer()
                HotKeyRecorder(setting: $ultra.hotKey)
                    .disabled(!ultra.hotKey.isEnabled)
            }
            if ultra.hotKey.isEnabled && hotKey.registrationFailed {
                Text("\(ultra.hotKey.displayName) 已被其他应用占用，请换一个组合。")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { loginItem.refresh() }
    }
}

/// 世界 tab: manage the world clock list.
struct WorldClockSettingsTab: View {
    @ObservedObject var settings: ClockSettings
    @ObservedObject var ultra: UltraSettings
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSectionTitle(title: "世界时钟")
            SettingsCard {
                if ultra.worldClocks.isEmpty {
                    Text("尚未添加城市")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                ForEach(ultra.worldClocks) { city in
                    let entry = TimeZoneSearch.entry(for: city.timeZoneIdentifier)
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                            Text("\(entry.localizedName) · \(entry.identifier) · \(entry.offsetLabel())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(WorldClockMath.differenceLabel(
                            seconds: WorldClockMath.offsetDifference(city.timeZone, relativeTo: settings.effectiveTimeZone, at: Date())
                        ))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        Button { ultra.moveWorldClock(id: city.id, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(ultra.worldClocks.first?.id == city.id)
                        Button { ultra.moveWorldClock(id: city.id, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(ultra.worldClocks.last?.id == city.id)
                        Button(role: .destructive) { ultra.removeWorldClock(id: city.id) } label: { Image(systemName: "trash") }
                    }
                    if city.id != ultra.worldClocks.last?.id {
                        Divider()
                    }
                }
                Divider()
                HStack {
                    Button {
                        isAdding = true
                    } label: {
                        Label("添加城市…", systemImage: "plus")
                    }
                    .popover(isPresented: $isAdding, arrowEdge: .bottom) {
                        TimeZoneSearchView(
                            current: nil,
                            recents: settings.recentTimeZoneIdentifiers,
                            suggestions: settings.quickTimeZoneChoices,
                            listHeight: 280,
                            onSelect: { identifier in
                                ultra.addWorldClock(identifier)
                                settings.noteRecentTimeZone(identifier)
                                isAdding = false
                            },
                            onCancel: { isAdding = false }
                        )
                        .padding(10)
                        .frame(width: 340)
                    }
                    Spacer()
                    Text("时差相对于菜单栏时钟的时区；本机时区会自动显示在面板最上方")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 日历与作息 tab: work-hours definition used by the 国内作息 status.
struct ScheduleSettingsTab: View {
    @ObservedObject var ultra: UltraSettings

    private let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSectionTitle(title: "国内作息")
            SettingsCard {
                Toggle("在面板中显示国内作息状态", isOn: $ultra.showsWorkStatus)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                HStack {
                    Text("参考时区")
                    Spacer()
                    TimeZoneSearchButton(
                        settings: ClockSettings.shared,
                        identifier: ultra.workSchedule.timeZoneIdentifier,
                        onSelect: { ultra.workSchedule.timeZoneIdentifier = $0 }
                    )
                    .frame(width: 290)
                }
                Divider()
                timeRow("上班", \.workStart, "下班", \.workEnd)
                Divider()
                timeRow("午休开始", \.lunchStart, "午休结束", \.lunchEnd)
                Divider()
                timeRow("深夜开始", \.nightStart, "起床", \.nightEnd)
                Divider()
                HStack {
                    Text("工作日")
                    Spacer()
                    ForEach(weekdayOrder, id: \.self) { weekday in
                        Toggle(Alarm.weekdaySymbols[weekday - 1], isOn: Binding(
                            get: { ultra.workSchedule.workdays.contains(weekday) },
                            set: { isOn in
                                if isOn {
                                    ultra.workSchedule.workdays.insert(weekday)
                                } else {
                                    ultra.workSchedule.workdays.remove(weekday)
                                }
                            }
                        ))
                        .toggleStyle(.button)
                    }
                }
                Text("法定节假日与调休没有内置（每年由国务院公布），这些日子请以实际安排为准。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsSectionTitle(title: "日历")
            SettingsCard {
                Text("农历由系统中国历法离线换算；二十四节气按太阳视黄经离线计算，与天文台公布时刻相差约十分钟以内，按北京时间取日期。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func timeRow(
        _ firstTitle: String,
        _ first: WritableKeyPath<WorkSchedule, Int>,
        _ secondTitle: String,
        _ second: WritableKeyPath<WorkSchedule, Int>
    ) -> some View {
        HStack {
            Text(firstTitle)
            MinuteOfDayPicker(minuteOfDay: Binding(
                get: { ultra.workSchedule[keyPath: first] },
                set: { ultra.workSchedule[keyPath: first] = $0 }
            ))
            Spacer()
            Text(secondTitle)
            MinuteOfDayPicker(minuteOfDay: Binding(
                get: { ultra.workSchedule[keyPath: second] },
                set: { ultra.workSchedule[keyPath: second] = $0 }
            ))
        }
    }
}

/// 闹钟 tab: the same list and editor as the panel, with more room.
struct AlarmSettingsTab: View {
    @ObservedObject var settings: ClockSettings
    @ObservedObject var ultra: UltraSettings
    @ObservedObject var scheduler = AlarmScheduler.shared
    @State private var draft: Alarm?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSectionTitle(title: "闹钟")
            SettingsCard {
                if ultra.alarms.isEmpty && draft == nil {
                    Text("还没有闹钟")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                ForEach(ultra.alarms) { alarm in
                    HStack(spacing: 12) {
                        Text(alarm.timeLabel)
                            .font(.title2.monospacedDigit())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alarm.displayLabel)
                            Text("\(TimeZoneSearch.entry(for: alarm.timeZoneIdentifier).title) · \(alarm.repeatLabel)\(alarm.speaks ? " · 朗读" : "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { alarm.isEnabled },
                            set: { ultra.setAlarm(id: alarm.id, enabled: $0) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        Button("编辑…") { draft = alarm }
                        Button(role: .destructive) { ultra.removeAlarm(id: alarm.id) } label: { Image(systemName: "trash") }
                    }
                    Divider()
                }
                if let draft {
                    AlarmEditor(
                        alarm: Binding(get: { draft }, set: { self.draft = $0 }),
                        settings: settings,
                        isNew: !ultra.alarms.contains { $0.id == draft.id },
                        onSave: { saved in
                            ultra.saveAlarm(saved)
                            AlarmScheduler.shared.requestAuthorizationIfNeeded()
                            self.draft = nil
                        },
                        onDelete: {
                            ultra.removeAlarm(id: draft.id)
                            self.draft = nil
                        },
                        onCancel: { self.draft = nil }
                    )
                    .frame(maxWidth: 360, alignment: .leading)
                } else {
                    HStack {
                        Button {
                            draft = Alarm(hour: 9, minute: 0, timeZoneIdentifier: settings.effectiveTimeZone.identifier, repeatDays: [2, 3, 4, 5, 6])
                        } label: {
                            Label("新建闹钟…", systemImage: "plus")
                        }
                        Spacer()
                        Text("闹钟按各自时区的时间响铃，Mac 睡眠时错过的会以通知提示")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if scheduler.notificationsDenied {
                    Text("通知权限已关闭：闹钟仍会播放声音，但不会显示横幅。可在 系统设置 › 通知 中开启。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
