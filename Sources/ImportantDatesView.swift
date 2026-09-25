import AppKit
import SwiftUI

extension ImportantDate.Kind {
    var tint: Color {
        switch self {
        case .birthday: return .pink
        case .anniversary: return .red
        case .exam: return .blue
        case .deadline: return .orange
        case .other: return .purple
        }
    }
}

// MARK: - Panel card

/// "重要日期" card under the calendar: the next few dates with countdowns, and an inline editor.
struct ImportantDatesCard: View {
    @ObservedObject var store = ImportantDateStore.shared
    @Binding var draft: ImportantDate?
    let namespace: Namespace.ID
    let openAll: () -> Void

    private let visibleCount = 3

    var body: some View {
        TimelineView(.everyMinute) { _ in
            let today = store.today
            VStack(alignment: .leading, spacing: 10) {
                if draft != nil {
                    ImportantDateEditor(
                        // Ignore writes after closing: the text field commits its value when it loses focus,
                        // which would otherwise reopen the editor with a blank date.
                        draft: Binding(get: { draft ?? ImportantDate(start: today) }, set: { if draft != nil { draft = $0 } }),
                        isNew: !store.items.contains { $0.id == draft?.id },
                        onSave: { item in
                            withAnimation(Metrics.spring) {
                                store.save(item)
                                draft = nil
                            }
                        },
                        onCancel: { withAnimation(Metrics.spring) { draft = nil } },
                        onDelete: { id in
                            withAnimation(Metrics.spring) {
                                store.remove(id: id)
                                draft = nil
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    list(today: today)
                        .transition(.opacity)
                }
            }
            .card(id: "important-dates", in: namespace)
        }
    }

    private func list(today: DayStamp) -> some View {
        let entries = store.upcoming(from: today)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "star.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.pink)
                Text("重要日期")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if entries.count > visibleCount {
                    Button("全部 \(entries.count) 项", action: openAll)
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Button {
                    withAnimation(Metrics.spring) { draft = ImportantDate(start: today) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .help("添加重要日期")
            }

            if entries.isEmpty {
                Text("添加生日、考试、报名截止等日期，到期前提醒你")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            } else {
                ForEach(entries.prefix(visibleCount)) { entry in
                    ImportantDateRow(entry: entry, today: today) {
                        withAnimation(Metrics.spring) { draft = entry.item }
                    }
                    .contextMenu {
                        Button("编辑…") { withAnimation(Metrics.spring) { draft = entry.item } }
                        Button("删除", role: .destructive) { store.remove(id: entry.item.id) }
                    }
                }
            }
        }
    }
}

/// One date with its kind, when it is, and a countdown. Tapping edits it.
struct ImportantDateRow: View {
    let entry: ImportantDateStore.Entry
    let today: DayStamp
    let onEdit: () -> Void

    var body: some View {
        let item = entry.item
        let countdown = item.countdown(for: entry.occurrence, today: today)
        Button(action: onEdit) {
            HStack(spacing: 10) {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(item.kind.tint.gradient))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        if let age = item.age(at: entry.occurrence) {
                            Text("\(age)岁")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(item.kind.tint)
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if let value = countdown.value, countdown.caption != "明天" {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(countdown.caption)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text(verbatim: "\(value)")
                                .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(countdown.caption == "已过去" ? Color.secondary : item.kind.tint)
                            Text(countdown.unit)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(countdown.caption)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(item.kind.tint.gradient))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("编辑「\(item.title)」")
    }

    private var subtitle: String {
        let item = entry.item
        var parts = [item.dateLabel(for: entry.occurrence)]
        if let lunar = item.lunarLabel { parts.append(lunar) }
        if item.repeatsYearly { parts.append("每年") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Editor

/// Add or edit one important date. Used inline in the panel and in a sheet in 详细设置.
struct ImportantDateEditor: View {
    @Binding var draft: ImportantDate
    let isNew: Bool
    let onSave: (ImportantDate) -> Void
    let onCancel: () -> Void
    let onDelete: (UUID) -> Void
    @ObservedObject private var store = ImportantDateStore.shared

    private static let reminderChoices: [(days: Int, title: String)] = [
        (0, "当天"), (1, "1天前"), (3, "3天前"), (7, "7天前"), (30, "30天前")
    ]
    private static let lunarMonthNames = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]

    /// Date pickers show local wall-clock days; stamps carry no zone, so the local calendar is only a vehicle.
    private let local = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isNew ? "添加重要日期" : "编辑重要日期")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            TextField("名称，例如 考研初试、妈妈生日", text: $draft.title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(.quaternary))

            kindPicker

            LiquidSegmentedControl(choices: ["某一天", "时间段"], selection: modeBinding)
                .disabled(draft.isLunar)
                .opacity(draft.isLunar ? 0.5 : 1)

            VStack(spacing: 8) {
                dateRows
                optionRow("每年重复", isOn: repeatBinding)
                if draft.end == nil {
                    optionRow("按农历", isOn: lunarBinding)
                }
                optionRow("具体时间", isOn: timeEnabledBinding) {
                    if draft.minuteOfDay != nil {
                        timePicker(minuteBinding(\.minuteOfDay, fallback: 8 * 60))
                    }
                }
            }

            reminderSection

            HStack(spacing: 8) {
                if !isNew {
                    Button("删除", role: .destructive) { onDelete(draft.id) }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button("保存") { onSave(cleaned) }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: Kind

    private var kindPicker: some View {
        HStack(spacing: 6) {
            ForEach(ImportantDate.Kind.allCases) { kind in
                let isSelected = draft.kind == kind
                Button {
                    withAnimation(Metrics.spring) {
                        if isNew && draft.kind.repeatsByDefault != kind.repeatsByDefault {
                            draft.repeatsYearly = kind.repeatsByDefault
                        }
                        draft.kind = kind
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 12, weight: .semibold))
                        Text(kind.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? AnyShapeStyle(kind.tint.gradient) : AnyShapeStyle(.quaternary))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Dates

    @ViewBuilder
    private var dateRows: some View {
        if draft.isLunar {
            labeledRow("日期") {
                Menu(Self.lunarMonthNames[(draft.start.month - 1) % 12]) {
                    ForEach(1...12, id: \.self) { month in
                        Button(Self.lunarMonthNames[month - 1]) { draft.start.month = month }
                    }
                }
                .fixedSize()
                Menu(lunarDayName(draft.start.day)) {
                    ForEach(1...30, id: \.self) { day in
                        Button(lunarDayName(day)) { draft.start.day = day }
                    }
                }
                .fixedSize()
            }
            if let next = draft.occurrence(onOrAfter: store.today) {
                Text(verbatim: "下一次：\(next.start.year)年\(ImportantDate.monthDay(next.start))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            labeledRow(draft.end == nil ? "日期" : "开始") {
                datePicker(dayBinding(\.start))
            }
            if draft.end != nil {
                labeledRow("结束") {
                    datePicker(endBinding, from: draft.start)
                }
            }
        }
    }

    private func datePicker(_ selection: Binding<Date>, from first: DayStamp? = nil) -> some View {
        Group {
            if let first {
                DatePicker("", selection: selection, in: first.date(in: local)..., displayedComponents: .date)
            } else {
                DatePicker("", selection: selection, displayedComponents: .date)
            }
        }
        .labelsHidden()
        .datePickerStyle(.stepperField)
        .environment(\.locale, Locale(identifier: "zh_CN"))
    }

    private func timePicker(_ selection: Binding<Date>) -> some View {
        DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.stepperField)
            .environment(\.locale, Locale(identifier: "zh_CN"))
    }

    private func lunarDayName(_ day: Int) -> String {
        LunarDate(cycleYear: 1, month: 1, day: day, isLeapMonth: false).dayName
    }

    // MARK: Reminders

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("提醒")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if !draft.reminderDays.isEmpty || (draft.end != nil && draft.remindsAtEnd) {
                    timePicker(minuteBinding(\.reminderMinute))
                }
            }
            HStack(spacing: 4) {
                ForEach(Self.reminderChoices, id: \.days) { choice in
                    let isOn = draft.reminderDays.contains(choice.days)
                    Button {
                        if isOn {
                            draft.reminderDays.removeAll { $0 == choice.days }
                        } else {
                            draft.reminderDays = (draft.reminderDays + [choice.days]).sorted()
                        }
                    } label: {
                        Text(choice.title)
                            .font(.system(size: 11, weight: isOn ? .semibold : .medium))
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(Capsule().fill(isOn ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            if draft.end != nil {
                optionRow("结束当天也提醒", isOn: $draft.remindsAtEnd)
            }
            if store.notificationsDenied {
                HStack(spacing: 6) {
                    Image(systemName: "bell.slash.fill")
                        .foregroundStyle(.orange)
                    Text("通知已关闭，提醒不会弹出")
                    Spacer()
                    Button("去打开") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.mini)
                }
                .font(.system(size: 11))
            }
        }
    }

    // MARK: Rows

    private func labeledRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12))
            Spacer()
            content()
        }
    }

    private func optionRow<Accessory: View>(
        _ title: String,
        isOn: Binding<Bool>,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12))
            Spacer()
            accessory()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    // MARK: Bindings

    private var modeBinding: Binding<String> {
        Binding(
            get: { draft.end == nil ? "某一天" : "时间段" },
            set: { mode in
                withAnimation(Metrics.spring) {
                    if mode == "时间段" {
                        draft.isLunar = false
                        draft.end = draft.end ?? draft.start.adding(days: 7)
                    } else {
                        draft.end = nil
                    }
                }
            }
        )
    }

    private var repeatBinding: Binding<Bool> {
        Binding(
            get: { draft.repeatsYearly },
            set: { value in
                draft.repeatsYearly = value
                // Lunar dates only make sense as yearly dates.
                if !value && draft.isLunar { setLunar(false) }
            }
        )
    }

    private var lunarBinding: Binding<Bool> {
        Binding(get: { draft.isLunar }, set: { value in withAnimation(Metrics.spring) { setLunar(value) } })
    }

    /// Converts between the Gregorian date shown and its lunar month/day, so switching keeps the same day.
    private func setLunar(_ lunar: Bool) {
        guard lunar != draft.isLunar else { return }
        if lunar {
            let date = LunarCalendar.lunarDate(year: draft.start.year, month: draft.start.month, day: draft.start.day)
            draft.start = DayStamp(year: draft.start.year, month: date.month, day: date.day)
            draft.repeatsYearly = true
            draft.isLunar = true
        } else {
            let next = draft.occurrence(onOrAfter: store.today)?.start ?? store.today
            draft.isLunar = false
            draft.start = next
        }
    }

    private var timeEnabledBinding: Binding<Bool> {
        Binding(
            get: { draft.minuteOfDay != nil },
            set: { value in withAnimation(Metrics.spring) { draft.minuteOfDay = value ? 8 * 60 + 30 : nil } }
        )
    }

    private func dayBinding(_ keyPath: WritableKeyPath<ImportantDate, DayStamp>) -> Binding<Date> {
        Binding(
            get: { draft[keyPath: keyPath].date(in: local) },
            set: { value in
                let day = DayStamp(value, calendar: local)
                draft[keyPath: keyPath] = day
                if let end = draft.end, end < day { draft.end = day }
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { (draft.end ?? draft.start).date(in: local) },
            set: { draft.end = max(DayStamp($0, calendar: local), draft.start) }
        )
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<ImportantDate, Int>) -> Binding<Date> {
        Binding(
            get: { local.date(bySettingHour: draft[keyPath: keyPath] / 60, minute: draft[keyPath: keyPath] % 60, second: 0, of: Date()) ?? Date() },
            set: { value in
                let parts = local.dateComponents([.hour, .minute], from: value)
                draft[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<ImportantDate, Int?>, fallback: Int) -> Binding<Date> {
        Binding(
            get: {
                let minute = draft[keyPath: keyPath] ?? fallback
                return local.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
            },
            set: { value in
                let parts = local.dateComponents([.hour, .minute], from: value)
                draft[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    /// Trimmed title and no stale fields for the chosen mode.
    private var cleaned: ImportantDate {
        var item = draft
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if item.isLunar { item.end = nil; item.repeatsYearly = true }
        return item
    }
}
