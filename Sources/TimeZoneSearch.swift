import AppKit
import SwiftUI

/// One searchable time zone with its precomputed match keys.
struct TimeZoneEntry: Identifiable, Hashable {
    let identifier: String
    /// Chinese city name when we know one, otherwise the city part of the identifier ("Los Angeles").
    let title: String
    /// Localized generic name, e.g. "中国时间".
    let localizedName: String
    fileprivate let keys: [String]

    var id: String { identifier }

    func offsetLabel(at date: Date = Date()) -> String {
        guard let zone = TimeZone(identifier: identifier) else { return "" }
        return TimeZoneSearch.offsetLabel(seconds: zone.secondsFromGMT(for: date))
    }
}

/// Fuzzy search over `TimeZone.knownTimeZoneIdentifiers` by identifier, Chinese / English names,
/// Chinese city aliases, abbreviations ("PST", "JST") and UTC offsets ("GMT+8", "+5:30").
enum TimeZoneSearch {
    static let all: [TimeZoneEntry] = {
        var identifiers = TimeZone.knownTimeZoneIdentifiers
        if !identifiers.contains("UTC") { identifiers.append("UTC") }
        return identifiers.map(makeEntry)
    }()

    private static let entriesByIdentifier = Dictionary(uniqueKeysWithValues: all.map { ($0.identifier, $0) })

    static func entry(for identifier: String) -> TimeZoneEntry {
        entriesByIdentifier[identifier] ?? makeEntry(identifier)
    }

    static func search(_ query: String, date: Date = Date()) -> [TimeZoneEntry] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return [] }

        let offset = parseOffset(needle)
        let abbreviationMatch = TimeZone.abbreviationDictionary[needle.uppercased()]

        var scored: [(entry: TimeZoneEntry, score: Int)] = []
        for entry in all {
            var best = Int.max
            if entry.identifier == abbreviationMatch { best = 0 }
            for key in entry.keys {
                if key == needle { best = min(best, 0); break }
                if key.hasPrefix(needle) { best = min(best, 1) }
                else if key.contains(needle) { best = min(best, 2) }
            }
            if let offset, TimeZone(identifier: entry.identifier)?.secondsFromGMT(for: date) == offset {
                // A pure offset query ("+8") is answered by the offset, not by abbreviation text.
                best = 0
            }
            if best != .max { scored.append((entry, best)) }
        }

        return scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            let lhsRank = popularity(lhs.entry.identifier)
            let rhsRank = popularity(rhs.entry.identifier)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.entry.identifier < rhs.entry.identifier
        }.map(\.entry)
    }

    static func offsetLabel(seconds: Int) -> String {
        let sign = seconds < 0 ? "−" : "+"
        let hours = abs(seconds) / 3600
        let minutes = abs(seconds) % 3600 / 60
        return minutes == 0 ? "UTC\(sign)\(hours)" : String(format: "UTC\(sign)%d:%02d", hours, minutes)
    }

    // MARK: - Private

    /// Well-known zones first, then any zone we have a Chinese name for, then the rest.
    private static let popularOrder = [
        "Asia/Shanghai", "America/New_York", "America/Los_Angeles", "Europe/London", "Asia/Tokyo",
        "Asia/Hong_Kong", "Asia/Singapore", "Asia/Taipei", "Europe/Paris", "Europe/Berlin",
        "Australia/Sydney", "Asia/Seoul", "Asia/Kolkata", "Asia/Calcutta", "Asia/Dubai",
        "America/Chicago", "America/Toronto", "America/Vancouver", "UTC"
    ]

    private static func popularity(_ identifier: String) -> Int {
        if let index = popularOrder.firstIndex(of: identifier) { return index }
        return cityAliases[identifier] != nil ? popularOrder.count : popularOrder.count + 1
    }

    private static let regionNames: [String: String] = [
        "Asia": "亚洲", "Europe": "欧洲", "Africa": "非洲", "America": "美洲",
        "Australia": "澳洲", "Pacific": "太平洋", "Atlantic": "大西洋", "Indian": "印度洋", "Antarctica": "南极洲"
    ]

    private static let chinese = Locale(identifier: "zh_CN")
    private static let english = Locale(identifier: "en_US")

    private static func makeEntry(_ identifier: String) -> TimeZoneEntry {
        let zone = TimeZone(identifier: identifier)
        let cityPart = identifier.split(separator: "/").last.map(String.init)?
            .replacingOccurrences(of: "_", with: " ") ?? identifier
        let aliases = cityAliases[identifier] ?? []
        let localizedName = zone?.localizedName(for: .generic, locale: chinese) ?? identifier

        var keys = [identifier, cityPart, localizedName] + aliases
        if let region = identifier.split(separator: "/").first.flatMap({ regionNames[String($0)] }) {
            keys.append(region)
        }
        if let zone {
            keys += [
                zone.localizedName(for: .standard, locale: chinese),
                zone.localizedName(for: .generic, locale: english),
                zone.localizedName(for: .standard, locale: english),
                zone.localizedName(for: .shortStandard, locale: english),
                zone.abbreviation()
            ].compactMap { $0 }
        }
        keys += TimeZone.abbreviationDictionary.filter { $0.value == identifier }.map(\.key)

        return TimeZoneEntry(
            identifier: identifier,
            title: aliases.first ?? cityPart,
            localizedName: localizedName,
            keys: Array(Set(keys.map(normalize)))
        )
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Parses "gmt+8", "utc-5", "+8", "+08:00", "+0530", "utc+5:30" into seconds from GMT.
    private static func parseOffset(_ text: String) -> Int? {
        var rest = Substring(text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "−", with: "-"))
        for prefix in ["utc", "gmt"] where rest.hasPrefix(prefix) {
            rest = rest.dropFirst(prefix.count)
        }
        if rest.isEmpty { return text.hasPrefix("utc") || text.hasPrefix("gmt") ? 0 : nil }
        guard let signCharacter = rest.first, signCharacter == "+" || signCharacter == "-" else { return nil }
        let sign = signCharacter == "-" ? -1 : 1
        let digits = rest.dropFirst()

        let hours: Int
        let minutes: Int
        if let colon = digits.firstIndex(of: ":") {
            guard let h = Int(digits[..<colon]), let m = Int(digits[digits.index(after: colon)...]) else { return nil }
            hours = h
            minutes = m
        } else if digits.count > 2, let value = Int(digits) {
            hours = value / 100
            minutes = value % 100
        } else if let value = Int(digits) {
            hours = value
            minutes = 0
        } else {
            return nil
        }
        guard hours <= 14, minutes < 60 else { return nil }
        return sign * (hours * 3600 + minutes * 60)
    }

    /// Chinese (and a few colloquial English) names for cities people actually search for.
    /// The first alias becomes the row title.
    private static let cityAliases: [String: [String]] = [
        "Asia/Shanghai": ["北京", "上海", "北京时间", "中国", "广州", "深圳", "beijing", "china", "prc"],
        "Asia/Hong_Kong": ["香港", "hk"],
        "Asia/Macau": ["澳门"],
        "Asia/Taipei": ["台北", "台湾"],
        "Asia/Urumqi": ["乌鲁木齐", "新疆"],
        "Asia/Tokyo": ["东京", "日本", "大阪"],
        "Asia/Seoul": ["首尔", "韩国"],
        "Asia/Singapore": ["新加坡"],
        "Asia/Kuala_Lumpur": ["吉隆坡", "马来西亚"],
        "Asia/Bangkok": ["曼谷", "泰国", "河内"],
        "Asia/Ho_Chi_Minh": ["胡志明市", "越南"],
        "Asia/Jakarta": ["雅加达", "印尼"],
        "Asia/Manila": ["马尼拉", "菲律宾"],
        "Asia/Kolkata": ["新德里", "印度", "孟买", "delhi", "mumbai"],
        "Asia/Calcutta": ["新德里", "印度", "孟买", "delhi", "mumbai", "kolkata"],
        "Asia/Saigon": ["胡志明市", "越南", "ho chi minh"],
        "Asia/Rangoon": ["仰光", "缅甸", "yangon"],
        "Asia/Katmandu": ["加德满都", "尼泊尔", "kathmandu"],
        "Asia/Dubai": ["迪拜", "阿联酋"],
        "Asia/Riyadh": ["利雅得", "沙特"],
        "Asia/Tehran": ["德黑兰", "伊朗"],
        "Asia/Karachi": ["卡拉奇", "巴基斯坦"],
        "Asia/Dhaka": ["达卡", "孟加拉"],
        "Asia/Kathmandu": ["加德满都", "尼泊尔"],
        "Asia/Yangon": ["仰光", "缅甸"],
        "Europe/London": ["伦敦", "英国", "uk"],
        "Europe/Dublin": ["都柏林", "爱尔兰"],
        "Europe/Lisbon": ["里斯本", "葡萄牙"],
        "Europe/Paris": ["巴黎", "法国"],
        "Europe/Berlin": ["柏林", "德国"],
        "Europe/Madrid": ["马德里", "西班牙"],
        "Europe/Rome": ["罗马", "意大利"],
        "Europe/Amsterdam": ["阿姆斯特丹", "荷兰"],
        "Europe/Zurich": ["苏黎世", "瑞士"],
        "Europe/Vienna": ["维也纳", "奥地利"],
        "Europe/Prague": ["布拉格", "捷克"],
        "Europe/Warsaw": ["华沙", "波兰"],
        "Europe/Stockholm": ["斯德哥尔摩", "瑞典"],
        "Europe/Helsinki": ["赫尔辛基", "芬兰"],
        "Europe/Athens": ["雅典", "希腊"],
        "Europe/Kyiv": ["基辅", "乌克兰"],
        "Europe/Kiev": ["基辅", "乌克兰"],
        "Europe/Istanbul": ["伊斯坦布尔", "土耳其"],
        "Europe/Moscow": ["莫斯科", "俄罗斯"],
        "Africa/Cairo": ["开罗", "埃及"],
        "Africa/Johannesburg": ["约翰内斯堡", "南非"],
        "Africa/Lagos": ["拉各斯", "尼日利亚"],
        "Africa/Nairobi": ["内罗毕", "肯尼亚"],
        "America/New_York": ["纽约", "华盛顿", "波士顿", "美东", "nyc", "new york"],
        "America/Chicago": ["芝加哥", "休斯顿", "美中"],
        "America/Denver": ["丹佛", "美山地"],
        "America/Phoenix": ["凤凰城"],
        "America/Los_Angeles": ["洛杉矶", "旧金山", "西雅图", "硅谷", "美西", "la", "sf", "san francisco", "seattle"],
        "America/Anchorage": ["安克雷奇", "阿拉斯加"],
        "Pacific/Honolulu": ["檀香山", "夏威夷"],
        "America/Toronto": ["多伦多", "蒙特利尔"],
        "America/Vancouver": ["温哥华"],
        "America/Mexico_City": ["墨西哥城", "墨西哥"],
        "America/Sao_Paulo": ["圣保罗", "巴西"],
        "America/Argentina/Buenos_Aires": ["布宜诺斯艾利斯", "阿根廷"],
        "America/Lima": ["利马", "秘鲁"],
        "America/Santiago": ["圣地亚哥", "智利"],
        "America/Bogota": ["波哥大", "哥伦比亚"],
        "Australia/Sydney": ["悉尼", "澳洲"],
        "Australia/Melbourne": ["墨尔本"],
        "Australia/Brisbane": ["布里斯班"],
        "Australia/Perth": ["珀斯"],
        "Australia/Adelaide": ["阿德莱德"],
        "Pacific/Auckland": ["奥克兰", "新西兰"],
        "UTC": ["协调世界时", "世界时", "utc", "gmt"]
    ]
}

/// Search field + result list. Used inline in the control panel and in a popover in the settings window.
struct TimeZoneSearchView: View {
    let current: String?
    let recents: [String]
    let suggestions: [String]
    let listHeight: CGFloat
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @State private var query: String
    @State private var highlighted = 0

    init(
        current: String?,
        recents: [String],
        suggestions: [String],
        listHeight: CGFloat = 196,
        initialQuery: String = "",
        onSelect: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.current = current
        self.recents = recents
        self.suggestions = suggestions
        self.listHeight = listHeight
        self.onSelect = onSelect
        self.onCancel = onCancel
        _query = State(initialValue: initialQuery)
    }

    private var sections: [(title: String?, entries: [TimeZoneEntry])] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            let recentEntries = recents.map(TimeZoneSearch.entry(for:))
            let quick = suggestions.filter { !recents.contains($0) }.map(TimeZoneSearch.entry(for:))
            return [("最近使用", recentEntries), ("常用", quick)].filter { !$0.1.isEmpty }
        }
        return [(nil, Array(TimeZoneSearch.search(query).prefix(60)))]
    }

    private var flatEntries: [TimeZoneEntry] { sections.flatMap(\.entries) }

    /// Shrinks the list for short result sets instead of leaving an empty scroll area.
    private var estimatedListHeight: CGFloat {
        let sections = sections
        let rows = sections.reduce(0) { $0 + $1.entries.count }
        let headers = sections.filter { $0.title != nil }.count
        return CGFloat(rows) * 37 + CGFloat(headers) * 19 + 2
    }

    var body: some View {
        let entries = flatEntries
        VStack(spacing: 6) {
            SearchField(
                text: $query,
                placeholder: "搜索城市、时区或 GMT+8",
                onMove: { delta in
                    guard !entries.isEmpty else { return }
                    highlighted = min(max(highlighted + delta, 0), entries.count - 1)
                },
                onSubmit: {
                    guard entries.indices.contains(highlighted) else { return }
                    onSelect(entries[highlighted].identifier)
                },
                onCancel: onCancel
            )
            .onChange(of: query) { _, _ in highlighted = 0 }

            if entries.isEmpty {
                Text("没有匹配的时区")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                                if let title = section.title {
                                    Text(title)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.top, 4)
                                }
                                ForEach(section.entries) { entry in
                                    let index = entries.firstIndex(of: entry) ?? 0
                                    row(entry, isHighlighted: index == highlighted)
                                        .id(entry.id)
                                        .onTapGesture { onSelect(entry.identifier) }
                                        .onHover { if $0 { highlighted = index } }
                                }
                            }
                        }
                    }
                    .frame(height: min(listHeight, estimatedListHeight))
                    .onChange(of: highlighted) { _, index in
                        guard entries.indices.contains(index) else { return }
                        proxy.scrollTo(entries[index].id)
                    }
                }
            }
        }
    }

    private func row(_ entry: TimeZoneEntry, isHighlighted: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isHighlighted ? Color.white : Color.accentColor)
                .opacity(entry.identifier == current ? 1 : 0)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text("\(entry.localizedName) · \(entry.identifier)")
                    .font(.system(size: 10))
                    .foregroundStyle(isHighlighted ? Color.white.opacity(0.8) : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(entry.offsetLabel())
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(isHighlighted ? Color.white.opacity(0.9) : Color.secondary)
        }
        .foregroundStyle(isHighlighted ? Color.white : Color.primary)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHighlighted ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

/// NSSearchField wrapper that routes ↑/↓/Return/Esc to the list instead of the field editor.
private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.focusRingType = .none
        field.sendsSearchStringImmediately = true
        field.controlSize = .regular
        field.font = .systemFont(ofSize: 12)
        field.stringValue = text
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0)
        }
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchField

        init(_ parent: SearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)):
                // First Esc clears the query, the second one closes the search.
                if parent.text.isEmpty {
                    parent.onCancel()
                } else {
                    parent.text = ""
                }
            default:
                return false
            }
            return true
        }
    }
}
