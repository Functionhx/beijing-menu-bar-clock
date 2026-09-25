import AppKit
import SwiftUI

/// "闹钟" tab: alarms in any time zone, edited inline.
struct AlarmsPanelSection: View {
    @ObservedObject var settings: ClockSettings
    @ObservedObject var ultra: UltraSettings
    @ObservedObject var scheduler = AlarmScheduler.shared
    /// Harness hook: open the editor for a new alarm right away.
    var startsEditing = false

    @State private var draft: Alarm?

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 6) {
                ModuleHeader(title: "闹钟") {
                    if draft == nil {
                        PillButton(title: "新建", symbol: "plus") { draft = newAlarm() }
                    }
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
                    Divider()
                }

                if ultra.alarms.isEmpty && draft == nil {
                    VStack(spacing: 4) {
                        Image(systemName: "alarm")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                        Text("还没有闹钟")
                            .font(.system(size: 12, weight: .medium))
                        Text("可以按任意时区设定，例如按北京时间提醒开会")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                } else {
                    VStack(spacing: 2) {
                        ForEach(ultra.alarms) { alarm in
                            alarmRow(alarm, now: context.date)
                        }
                    }
                }

                if scheduler.notificationsDenied {
                    Button {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    } label: {
                        Label("通知已关闭，闹钟只会播放声音 · 打开系统设置", systemImage: "bell.slash")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .moduleBackground()
        }
        .onAppear {
            if startsEditing && draft == nil { draft = newAlarm() }
        }
    }

    private func newAlarm() -> Alarm {
        Alarm(hour: 9, minute: 0, timeZoneIdentifier: settings.effectiveTimeZone.identifier, repeatDays: [2, 3, 4, 5, 6])
    }

    private func alarmRow(_ alarm: Alarm, now: Date) -> some View {
        let zoneTitle = TimeZoneSearch.entry(for: alarm.timeZoneIdentifier).title
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(alarm.timeLabel)
                        .font(.system(size: 22, weight: .medium, design: .rounded).monospacedDigit())
                    Text(zoneTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text("\(alarm.displayLabel) · \(alarm.repeatLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if alarm.isEnabled, let next = alarm.nextFireDate(after: now) {
                    Text(nextLabel(next, alarm: alarm, now: now))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .opacity(alarm.isEnabled ? 1 : 0.5)
            Spacer(minLength: 4)
            Toggle("", isOn: Binding(
                get: { alarm.isEnabled },
                set: { ultra.setAlarm(id: alarm.id, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
        .onTapGesture { draft = alarm }
        .contextMenu {
            Button("编辑…") { draft = alarm }
            Button("删除", role: .destructive) { ultra.removeAlarm(id: alarm.id) }
        }
    }

    /// "下次 明天 07:00 · 北京 19:00" — the second part only when the alarm's zone differs from the clock's.
    private func nextLabel(_ next: Date, alarm: Alarm, now: Date) -> String {
        let reference = settings.effectiveTimeZone
        let alarmCalendar = WorldClockMath.calendar(in: alarm.timeZone)
        let dayOffset = alarmCalendar.dateComponents(
            [.day],
            from: alarmCalendar.startOfDay(for: now),
            to: alarmCalendar.startOfDay(for: next)
        ).day ?? 0
        let when: String
        switch dayOffset {
        case 0: when = "今天"
        case 1: when = "明天"
        case 2: when = "后天"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.timeZone = alarm.timeZone
            formatter.dateFormat = "M月d日 EEE"
            when = formatter.string(from: next)
        }
        var text = "下次 \(when) \(alarm.timeLabel)"
        if reference.secondsFromGMT(for: next) != alarm.timeZone.secondsFromGMT(for: next) {
            let formatter = DateFormatter()
            formatter.timeZone = reference
            formatter.dateFormat = "HH:mm"
            text += " · \(settings.effectiveZoneTitle) \(formatter.string(from: next))"
        }
        return text
    }
}

/// Inline alarm form: time, zone (searchable), label, repeat days, voice.
struct AlarmEditor: View {
    @Binding var alarm: Alarm
    @ObservedObject var settings: ClockSettings
    let isNew: Bool
    let onSave: (Alarm) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var isPickingZone = false

    /// Monday-first display order of Gregorian weekdays.
    private let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                MinuteOfDayPicker(minuteOfDay: Binding(
                    get: { alarm.hour * 60 + alarm.minute },
                    set: {
                        alarm.hour = $0 / 60
                        alarm.minute = $0 % 60
                    }
                ))
                Button {
                    isPickingZone.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "globe")
                        Text(TimeZoneSearch.entry(for: alarm.timeZoneIdentifier).title)
                        Image(systemName: isPickingZone ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("闹钟按这个时区的时间响铃")
                Spacer()
            }

            if isPickingZone {
                TimeZoneSearchView(
                    current: alarm.timeZoneIdentifier,
                    recents: settings.recentTimeZoneIdentifiers,
                    suggestions: settings.quickTimeZoneChoices,
                    listHeight: 150,
                    onSelect: { identifier in
                        alarm.timeZoneIdentifier = identifier
                        settings.noteRecentTimeZone(identifier)
                        isPickingZone = false
                    },
                    onCancel: { isPickingZone = false }
                )
            }

            TextField("标签（如：和国内开会）", text: $alarm.label)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            HStack(spacing: 4) {
                ForEach(weekdayOrder, id: \.self) { weekday in
                    let isOn = alarm.repeatDays.contains(weekday)
                    Button {
                        if isOn { alarm.repeatDays.remove(weekday) } else { alarm.repeatDays.insert(weekday) }
                    } label: {
                        Text(Alarm.weekdaySymbols[weekday - 1])
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(isOn ? Color.accentColor : Color.primary.opacity(0.08)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 2)
                Text(alarm.repeatLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Toggle("响铃时播放报时声音并朗读标签", isOn: $alarm.speaks)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

            HStack {
                if !isNew {
                    Button("删除", role: .destructive, action: onDelete)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("取消", action: onCancel)
                Button(isNew ? "添加" : "保存") {
                    var saved = alarm
                    saved.isEnabled = true
                    onSave(saved)
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
    }
}
