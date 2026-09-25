import Foundation

// Logic checks for ImportantDate (compiled with ImportantDate.swift + LunarCalendar.swift by scripts/test-logic.sh).
var failures = 0
func check<T: Equatable>(_ label: String, _ actual: T, _ expected: T) {
    if actual == expected { print("ok   \(label)") } else { failures += 1; print("FAIL \(label): got \(actual), expected \(expected)") }
}
func d(_ y: Int, _ m: Int, _ day: Int) -> DayStamp { DayStamp(year: y, month: m, day: day) }
typealias Occ = ImportantDate.Occurrence

let today = d(2026, 9, 25)

// One-off exam day
let exam = ImportantDate(title: "考研初试", kind: .exam, start: d(2026, 12, 20), minuteOfDay: 8 * 60 + 30)
let examOcc = exam.occurrence(onOrAfter: today)
check("exam next", examOcc, Occ(start: d(2026, 12, 20), end: d(2026, 12, 20)))
check("exam countdown", exam.countdown(for: examOcc!, today: today).text, "还有 86 天")
check("exam label", exam.dateLabel(for: examOcc!), "12月20日 08:30")
check("exam passed", exam.occurrence(onOrAfter: d(2026, 12, 21)), nil)
check("exam passed text", exam.countdown(for: exam.lastOccurrence(before: d(2026, 12, 23))!, today: d(2026, 12, 23)).text, "已过去 3 天")
check("exam tomorrow", exam.countdown(for: examOcc!, today: d(2026, 12, 19)).text, "明天")
check("exam today", exam.countdown(for: examOcc!, today: d(2026, 12, 20)).text, "就是今天")

// Registration period
let signup = ImportantDate(title: "考研报名", kind: .deadline, start: d(2026, 10, 10), end: d(2026, 10, 31))
let signupOcc = signup.occurrence(onOrAfter: d(2026, 10, 15))!
check("period label", signup.dateLabel(for: signupOcc), "10月10日–10月31日")
check("period in progress", signup.countdown(for: signupOcc, today: d(2026, 10, 15)).text, "进行中 · 还剩 16 天")
check("period last day", signup.countdown(for: signupOcc, today: d(2026, 10, 31)).text, "今天截止")
check("period over", signup.occurrence(onOrAfter: d(2026, 11, 1)), nil)
check("period grid", signup.occurrences(from: d(2026, 10, 1), through: d(2026, 10, 31)).count, 1)
check("period grid other month", signup.occurrences(from: d(2026, 11, 1), through: d(2026, 11, 30)).count, 0)

// Yearly Gregorian birthday with age
let birthday = ImportantDate(title: "妈妈", kind: .birthday, start: d(1994, 3, 2), repeatsYearly: true)
let birthdayOcc = birthday.occurrence(onOrAfter: today)!
check("birthday next", birthdayOcc, Occ(start: d(2027, 3, 2), end: d(2027, 3, 2)))
check("birthday age", birthday.age(at: birthdayOcc), 33)
check("birthday this year", birthday.occurrence(onOrAfter: d(2026, 3, 2))?.start, d(2026, 3, 2))
check("birthday not before birth", birthday.occurrences(from: d(1993, 1, 1), through: d(1993, 12, 31)).count, 0)

// 2月29日 in common years
let leap = ImportantDate(title: "leap", kind: .birthday, start: d(2000, 2, 29), repeatsYearly: true)
check("feb29 common year", leap.occurrence(onOrAfter: today)?.start, d(2027, 2, 28))
check("feb29 leap year", leap.occurrence(onOrAfter: d(2028, 1, 1))?.start, d(2028, 2, 29))

// Yearly period across New Year
let holiday = ImportantDate(title: "跨年", kind: .other, start: d(2020, 12, 28), end: d(2021, 1, 3), repeatsYearly: true)
check("wrap in progress", holiday.occurrence(onOrAfter: d(2027, 1, 2)), Occ(start: d(2026, 12, 28), end: d(2027, 1, 3)))
check("wrap label", holiday.dateLabel(for: holiday.occurrence(onOrAfter: d(2027, 1, 2))!), "12月28日–2027年1月3日")
check("wrap grid jan", holiday.occurrences(from: d(2027, 1, 1), through: d(2027, 1, 31)).map(\.start), [d(2026, 12, 28)])

// Lunar yearly dates
let midAutumn = ImportantDate(title: "中秋", kind: .other, start: d(2026, 8, 15), repeatsYearly: true, isLunar: true)
check("lunar today", midAutumn.occurrence(onOrAfter: today)?.start, d(2026, 9, 25))
check("lunar next year", midAutumn.occurrence(onOrAfter: d(2026, 9, 26))?.start, d(2027, 9, 15))
check("lunar label", midAutumn.lunarLabel, "农历八月十五")
let springFestival = ImportantDate(title: "春节", kind: .other, start: d(2026, 1, 1), repeatsYearly: true, isLunar: true)
check("lunar new year", springFestival.occurrence(onOrAfter: today)?.start, d(2027, 2, 6))
let eve = ImportantDate(title: "除夕", kind: .other, start: d(2026, 12, 30), repeatsYearly: true, isLunar: true)
check("lunar 三十 falls back to 廿九", eve.occurrence(onOrAfter: d(2026, 1, 1))?.start, d(2026, 2, 16))
check("lunar grid", midAutumn.occurrences(from: d(2026, 9, 1), through: d(2026, 9, 30)).map(\.start), [d(2026, 9, 25)])

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
