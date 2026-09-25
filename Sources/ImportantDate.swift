import Foundation

/// A calendar day without a time or time zone.
struct DayStamp: Codable, Hashable, Comparable {
    var year: Int
    var month: Int
    var day: Int

    static func < (lhs: DayStamp, rhs: DayStamp) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Midnight of this day in the calendar's time zone.
    func date(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    func adding(days: Int) -> DayStamp {
        let calendar = ImportantDate.utcCalendar
        return DayStamp(calendar.date(byAdding: .day, value: days, to: date(in: calendar)) ?? Date(), calendar: calendar)
    }

    func days(until other: DayStamp) -> Int {
        let calendar = ImportantDate.utcCalendar
        return calendar.dateComponents([.day], from: date(in: calendar), to: other.date(in: calendar)).day ?? 0
    }

    /// The same month and day in another year; 2月29日 becomes 2月28日 in common years.
    func moved(toYear newYear: Int) -> DayStamp {
        let calendar = ImportantDate.utcCalendar
        let first = calendar.date(from: DateComponents(year: newYear, month: month, day: 1)) ?? Date()
        let length = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        return DayStamp(year: newYear, month: month, day: min(day, length))
    }
}

/// Something worth remembering: a birthday, an exam day, a registration period…
struct ImportantDate: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case birthday, anniversary, exam, deadline, other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .birthday: return "生日"
            case .anniversary: return "纪念日"
            case .exam: return "考试"
            case .deadline: return "截止"
            case .other: return "其他"
            }
        }

        var symbol: String {
            switch self {
            case .birthday: return "gift.fill"
            case .anniversary: return "heart.fill"
            case .exam: return "pencil.and.list.clipboard"
            case .deadline: return "flag.checkered"
            case .other: return "star.fill"
            }
        }

        /// Birthdays and anniversaries come back every year; exams and deadlines usually don't.
        var repeatsByDefault: Bool {
            self == .birthday || self == .anniversary
        }
    }

    var id = UUID()
    var title: String
    var kind: Kind
    /// First day. For lunar dates `month`/`day` are the lunar month and day (year is only the reference year).
    var start: DayStamp
    /// Last day of a time period (Gregorian only); nil for a single day.
    var end: DayStamp?
    /// Optional time of day, e.g. an exam starting at 08:30.
    var minuteOfDay: Int?
    var repeatsYearly: Bool
    /// Yearly on a lunar month and day (single days only), e.g. a 农历 birthday.
    var isLunar: Bool
    /// Days before the (next) start to remind; 0 is the day itself.
    var reminderDays: [Int]
    var reminderMinute: Int
    /// For periods: also remind on the last day ("今天截止").
    var remindsAtEnd: Bool

    init(
        title: String = "",
        kind: Kind = .other,
        start: DayStamp,
        end: DayStamp? = nil,
        minuteOfDay: Int? = nil,
        repeatsYearly: Bool = false,
        isLunar: Bool = false,
        reminderDays: [Int] = [0, 1],
        reminderMinute: Int = 9 * 60,
        remindsAtEnd: Bool = true
    ) {
        self.title = title
        self.kind = kind
        self.start = start
        self.end = end
        self.minuteOfDay = minuteOfDay
        self.repeatsYearly = repeatsYearly
        self.isLunar = isLunar
        self.reminderDays = reminderDays
        self.reminderMinute = reminderMinute
        self.remindsAtEnd = remindsAtEnd
    }

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    var isPeriod: Bool { end != nil && !isLunar }

    /// One concrete Gregorian occurrence.
    struct Occurrence: Equatable {
        let start: DayStamp
        let end: DayStamp

        func contains(_ day: DayStamp) -> Bool { start <= day && day <= end }
    }

    /// Length of a period in days after the start (0 for single days).
    private var extraDays: Int {
        guard isPeriod, let end else { return 0 }
        return max(0, start.days(until: end))
    }

    /// The occurrence that is in progress on `day` or comes next; nil once a one-off date has passed.
    func occurrence(onOrAfter day: DayStamp) -> Occurrence? {
        if isLunar {
            return nextLunarDay(onOrAfter: day).map { Occurrence(start: $0, end: $0) }
        }
        guard repeatsYearly else {
            let occurrence = Occurrence(start: start, end: start.adding(days: extraDays))
            return occurrence.end >= day ? occurrence : nil
        }
        for year in (day.year - 1)...(day.year + 1) where year >= start.year {
            let first = start.moved(toYear: year)
            let occurrence = Occurrence(start: first, end: first.adding(days: extraDays))
            if occurrence.end >= day { return occurrence }
        }
        return nil
    }

    /// The most recent occurrence that ended before `day` (for "已过去" on one-off dates).
    func lastOccurrence(before day: DayStamp) -> Occurrence? {
        guard !repeatsYearly, !isLunar else { return nil }
        let occurrence = Occurrence(start: start, end: start.adding(days: extraDays))
        return occurrence.end < day ? occurrence : nil
    }

    /// Occurrences overlapping the given days (inclusive), for marking a month grid.
    func occurrences(from first: DayStamp, through last: DayStamp) -> [Occurrence] {
        if isLunar {
            var result: [Occurrence] = []
            var day = first
            while day <= last {
                if matchesLunar(day) { result.append(Occurrence(start: day, end: day)) }
                day = day.adding(days: 1)
            }
            return result
        }
        let years = repeatsYearly ? Array((first.year - 1)...last.year).filter { $0 >= start.year } : [start.year]
        return years.compactMap { year in
            let begin = repeatsYearly ? start.moved(toYear: year) : start
            let occurrence = Occurrence(start: begin, end: begin.adding(days: extraDays))
            return occurrence.end >= first && occurrence.start <= last ? occurrence : nil
        }
    }

    // MARK: Lunar

    private func nextLunarDay(onOrAfter day: DayStamp) -> DayStamp? {
        var candidate = day
        for _ in 0..<400 {
            if matchesLunar(candidate) { return candidate }
            candidate = candidate.adding(days: 1)
        }
        return nil
    }

    /// True on the Gregorian day of this item's lunar month and day. Leap months are skipped, and 三十 falls
    /// back to 廿九 in months that only have 29 days.
    private func matchesLunar(_ day: DayStamp) -> Bool {
        let lunar = LunarCalendar.lunarDate(year: day.year, month: day.month, day: day.day)
        guard !lunar.isLeapMonth, lunar.month == start.month else { return false }
        if lunar.day == start.day { return true }
        guard start.day == 30, lunar.day == 29 else { return false }
        let next = day.adding(days: 1)
        return LunarCalendar.lunarDate(year: next.year, month: next.month, day: next.day).day == 1
    }

    // MARK: Text

    /// "12月20日 08:30", "10月10日–10月31日", "每年农历八月十五 · 今年9月25日"
    func dateLabel(for occurrence: Occurrence) -> String {
        var text = Self.monthDay(occurrence.start)
        if occurrence.end != occurrence.start {
            text += "–" + (occurrence.end.year == occurrence.start.year ? "" : "\(occurrence.end.year)年") + Self.monthDay(occurrence.end)
        }
        if let minuteOfDay {
            text += " " + Self.timeLabel(minuteOfDay)
        }
        return text
    }

    /// "农历八月十五" for lunar items, nil otherwise.
    var lunarLabel: String? {
        guard isLunar else { return nil }
        let name = LunarDate(cycleYear: 1, month: start.month, day: start.day, isLeapMonth: false)
        return "农历\(name.monthName)\(name.dayName)"
    }

    /// Age reached on a Gregorian birthday, when the birth year is known.
    func age(at occurrence: Occurrence) -> Int? {
        guard kind == .birthday, repeatsYearly, !isLunar, start.year >= 1900 else { return nil }
        let age = occurrence.start.year - start.year
        return age > 0 ? age : nil
    }

    /// Countdown relative to `today`: "还有 86 天", "明天", "就是今天", "进行中 · 还剩 5 天", "今天截止".
    func countdown(for occurrence: Occurrence, today: DayStamp) -> Countdown {
        if today < occurrence.start {
            let days = today.days(until: occurrence.start)
            return Countdown(value: days, unit: "天", caption: days == 1 ? "明天" : "还有")
        }
        if occurrence.contains(today) {
            if occurrence.start == occurrence.end {
                return Countdown(value: nil, unit: "", caption: "就是今天")
            }
            let left = today.days(until: occurrence.end)
            return left == 0
                ? Countdown(value: nil, unit: "", caption: "今天截止")
                : Countdown(value: left, unit: "天", caption: "进行中 · 还剩")
        }
        return Countdown(value: occurrence.end.days(until: today), unit: "天", caption: "已过去")
    }

    struct Countdown: Equatable {
        let value: Int?
        let unit: String
        let caption: String

        var text: String {
            guard let value else { return caption }
            if caption == "明天" { return caption }
            return "\(caption) \(value) \(unit)"
        }
    }

    static func monthDay(_ day: DayStamp) -> String {
        "\(day.month)月\(day.day)日"
    }

    static func timeLabel(_ minuteOfDay: Int) -> String {
        String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }
}
