import AppKit
import SwiftUI

extension ClockSettings {
    /// City-style name of the clock's zone ("北京", "纽约"), following the system zone if selected.
    var effectiveZoneTitle: String {
        TimeZoneSearch.entry(for: effectiveTimeZone.identifier).title
    }
}

/// "世界" tab: world clock list plus the time converter that drives it.
struct WorldClockPanelSection: View {
    @ObservedObject var settings: ClockSettings
    @ObservedObject var ultra: UltraSettings
    /// Harness hook: start with the converter at this minute of the day.
    var initialScrubMinute: Int?

    @State private var isAdding = false
    @State private var isEditing = false
    @State private var scrubMinute: Int?
    @State private var copied = false

    init(settings: ClockSettings, ultra: UltraSettings, initialScrubMinute: Int? = nil) {
        self.settings = settings
        self.ultra = ultra
        self.initialScrubMinute = initialScrubMinute
        _scrubMinute = State(initialValue: initialScrubMinute)
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let reference = settings.effectiveTimeZone
            let instant = scrubMinute.map {
                WorldClockMath.date(atMinuteOfDay: $0, sameDayAs: context.date, in: reference)
            } ?? context.date
            VStack(spacing: 10) {
                worldModule(at: instant, reference: reference)
                converterModule(now: context.date, instant: instant, reference: reference)
            }
        }
    }

    // MARK: World clock

    private struct Row: Identifiable {
        let id: String
        let cityID: UUID?
        let title: String
        let zone: TimeZone
    }

    /// The Mac's own zone first (when it differs from the clock's), then the user's cities.
    private func rows(reference: TimeZone) -> [Row] {
        var rows: [Row] = []
        let local = TimeZone.current
        let citiesContainLocal = ultra.worldClocks.contains { $0.timeZoneIdentifier == local.identifier }
        if local.identifier != reference.identifier && !citiesContainLocal {
            rows.append(Row(id: "local", cityID: nil, title: "本地 · \(TimeZoneSearch.entry(for: local.identifier).title)", zone: local))
        }
        rows += ultra.worldClocks.map { city in
            let title = TimeZoneSearch.entry(for: city.timeZoneIdentifier).title
            return Row(
                id: city.id.uuidString,
                cityID: city.id,
                title: city.timeZoneIdentifier == local.identifier ? "\(title) · 本地" : title,
                zone: city.timeZone
            )
        }
        return rows
    }

    private func worldModule(at instant: Date, reference: TimeZone) -> some View {
        let rows = rows(reference: reference)
        return VStack(alignment: .leading, spacing: 6) {
            ModuleHeader(title: scrubMinute == nil ? "世界时钟" : "世界时钟 · 换算中") {
                if !ultra.worldClocks.isEmpty && !isAdding {
                    PillButton(title: isEditing ? "完成" : "编辑", symbol: nil) { isEditing.toggle() }
                }
                PillButton(title: isAdding ? "完成" : "添加", symbol: isAdding ? nil : "plus") {
                    isAdding.toggle()
                    isEditing = false
                }
            }

            if isAdding {
                TimeZoneSearchView(
                    current: nil,
                    recents: settings.recentTimeZoneIdentifiers,
                    suggestions: settings.quickTimeZoneChoices,
                    listHeight: 168,
                    onSelect: { identifier in
                        ultra.addWorldClock(identifier)
                        settings.noteRecentTimeZone(identifier)
                        isAdding = false
                    },
                    onCancel: { isAdding = false }
                )
            }

            if rows.isEmpty {
                Text("添加城市，随时查看各地时间")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 2) {
                    ForEach(rows) { row in
                        worldRow(row, at: instant, reference: reference)
                    }
                }
            }
        }
        .padding(8)
        .moduleBackground()
    }

    private func worldRow(_ row: Row, at instant: Date, reference: TimeZone) -> some View {
        let hour = WorldClockMath.hour(of: instant, in: row.zone)
        let isDay = WorldClockMath.isDaytime(hour: hour)
        let dayOffset = WorldClockMath.dayOffset(of: instant, in: row.zone, relativeTo: reference)
        let difference = WorldClockMath.offsetDifference(row.zone, relativeTo: reference, at: instant)
        return HStack(spacing: 8) {
            Image(systemName: isDay ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 12))
                .foregroundStyle(isDay ? Color.orange : Color.indigo)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text("\(WorldClockMath.dayOffsetLabel(dayOffset)) · \(WorldClockMath.differenceLabel(seconds: difference))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Text(format(instant, "HH:mm", in: row.zone))
                .font(.system(size: 20, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(scrubMinute == nil ? Color.primary : Color.accentColor)

            if isEditing, let id = row.cityID {
                HStack(spacing: 2) {
                    iconButton("chevron.up", help: "上移") { ultra.moveWorldClock(id: id, by: -1) }
                        .disabled(ultra.worldClocks.first?.id == id)
                    iconButton("chevron.down", help: "下移") { ultra.moveWorldClock(id: id, by: 1) }
                        .disabled(ultra.worldClocks.last?.id == id)
                    iconButton("minus.circle.fill", help: "移除", tint: .red) { ultra.removeWorldClock(id: id) }
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
        .contextMenu {
            if let id = row.cityID {
                Button("上移") { ultra.moveWorldClock(id: id, by: -1) }
                Button("下移") { ultra.moveWorldClock(id: id, by: 1) }
                Divider()
                Button("移除", role: .destructive) { ultra.removeWorldClock(id: id) }
            }
        }
        .help(row.zone.identifier)
    }

    private func iconButton(_ symbol: String, help: String, tint: Color = .secondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Converter

    private func converterModule(now: Date, instant: Date, reference: TimeZone) -> some View {
        let currentMinute = WorldClockMath.minuteOfDay(of: now, in: reference)
        return VStack(alignment: .leading, spacing: 6) {
            ModuleHeader(title: "时差换算") {
                if scrubMinute != nil {
                    PillButton(title: "现在", symbol: "arrow.uturn.backward") { scrubMinute = nil }
                }
                PillButton(title: copied ? "已复制" : "复制", symbol: copied ? "checkmark" : "doc.on.doc") {
                    copy(instant: instant, reference: reference)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(settings.effectiveZoneTitle)
                    .font(.system(size: 12, weight: .medium))
                Text(format(instant, "HH:mm", in: reference))
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                Spacer()
                Text(scrubMinute == nil ? "拖动滑块查看各地对应时间" : "上方已显示各地对应时间")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 3) {
                DayNightBar()
                    .frame(height: 5)
                    .padding(.horizontal, 2)
                Slider(
                    value: Binding(
                        get: { Double(scrubMinute ?? currentMinute) },
                        set: { scrubMinute = Int($0) }
                    ),
                    in: 0...(24 * 60 - 15),
                    step: 15
                )
                .controlSize(.small)
                HStack {
                    ForEach(["0:00", "6:00", "12:00", "18:00", "24:00"], id: \.self) { label in
                        Text(label)
                        if label != "24:00" { Spacer() }
                    }
                }
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .moduleBackground()
    }

    /// "北京 15:00 = 纽约 03:00 = 伦敦 08:00（明天）"
    private func copy(instant: Date, reference: TimeZone) {
        var parts = ["\(settings.effectiveZoneTitle) \(format(instant, "HH:mm", in: reference))"]
        for row in rows(reference: reference) {
            let offset = WorldClockMath.dayOffset(of: instant, in: row.zone, relativeTo: reference)
            let suffix = offset == 0 ? "" : "（\(WorldClockMath.dayOffsetLabel(offset))）"
            parts.append("\(row.title) \(format(instant, "HH:mm", in: row.zone))\(suffix)")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(parts.joined(separator: " = "), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func format(_ date: Date, _ pattern: String, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = zone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

/// Night → day → night gradient under the converter slider (00:00 … 24:00).
private struct DayNightBar: View {
    var body: some View {
        let night = Color.indigo.opacity(0.55)
        let dawn = Color.orange.opacity(0.55)
        let day = Color.yellow.opacity(0.6)
        Capsule()
            .fill(LinearGradient(
                stops: [
                    .init(color: night, location: 0),
                    .init(color: night, location: 5 / 24),
                    .init(color: dawn, location: 6.5 / 24),
                    .init(color: day, location: 9 / 24),
                    .init(color: day, location: 16 / 24),
                    .init(color: dawn, location: 18 / 24),
                    .init(color: night, location: 20 / 24),
                    .init(color: night, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ))
    }
}
