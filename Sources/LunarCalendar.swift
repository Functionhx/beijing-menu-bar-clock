import Foundation

/// Chinese lunar date for a Gregorian day, computed offline with `Calendar(identifier: .chinese)`.
/// Lunar dates are defined by Beijing time, so conversions always use Asia/Shanghai.
struct LunarDate: Equatable {
    let cycleYear: Int
    let month: Int
    let day: Int
    let isLeapMonth: Bool

    private static let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    private static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    private static let zodiac = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"]
    private static let monthNames = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
    private static let dayTens = ["初", "十", "廿", "三"]
    private static let digits = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

    /// "丙午"
    var yearName: String {
        let index = (cycleYear - 1) % 60
        return Self.stems[index % 10] + Self.branches[index % 12]
    }

    /// "马"
    var zodiacName: String {
        Self.zodiac[(cycleYear - 1) % 12]
    }

    /// "正月", "闰六月"
    var monthName: String {
        (isLeapMonth ? "闰" : "") + Self.monthNames[(month - 1) % 12]
    }

    /// "初一", "十五", "廿三", "三十"
    var dayName: String {
        switch day {
        case 10: return "初十"
        case 20: return "二十"
        case 30: return "三十"
        default: return Self.dayTens[day / 10] + Self.digits[(day - 1) % 10]
        }
    }

    /// Month name on the first day, day name otherwise — the convention for calendar cells.
    var cellLabel: String {
        day == 1 ? monthName : dayName
    }

    /// "丙午马年 八月初四"
    var fullName: String {
        "\(yearName)\(zodiacName)年 \(monthName)\(dayName)"
    }
}

enum LunarCalendar {
    static let beijing = TimeZone(identifier: "Asia/Shanghai")!

    private static let chinese: Calendar = {
        var calendar = Calendar(identifier: .chinese)
        calendar.timeZone = beijing
        return calendar
    }()

    /// Lunar date of the Gregorian calendar day `year-month-day`.
    static func lunarDate(year: Int, month: Int, day: Int) -> LunarDate {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = beijing
        // Noon avoids any ambiguity around midnight.
        let noon = gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
        return lunarDate(for: noon)
    }

    /// Lunar date of the Beijing calendar day containing `date`.
    static func lunarDate(for date: Date) -> LunarDate {
        let parts = chinese.dateComponents([.year, .month, .day, .isLeapMonth], from: date)
        return LunarDate(
            cycleYear: parts.year ?? 1,
            month: parts.month ?? 1,
            day: parts.day ?? 1,
            isLeapMonth: parts.isLeapMonth ?? false
        )
    }
}
