import Foundation

// Plain assertions for the ultra edition's pure logic. Run with scripts/test-logic.sh.

var failures = 0
var checks = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    checks += 1
    if !condition() {
        failures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

func zone(_ identifier: String) -> TimeZone { TimeZone(identifier: identifier)! }

func instant(_ text: String) -> Date {
    // ISO 8601 with explicit offset, e.g. "2026-03-08T06:30:00Z".
    ISO8601DateFormatter().date(from: text)!
}

let beijing = zone("Asia/Shanghai")
let newYork = zone("America/New_York")
let london = zone("Europe/London")
let kolkata = zone("Asia/Kolkata")

// MARK: World clock math across DST

// 2026-03-08 is the US spring-forward day (02:00 EST → 03:00 EDT at 07:00 UTC).
let beforeSpring = instant("2026-03-08T06:30:00Z")
let afterSpring = instant("2026-03-08T07:30:00Z")
expect(WorldClockMath.offsetDifference(newYork, relativeTo: beijing, at: beforeSpring) == -13 * 3600, "NY is 13h behind Beijing before DST")
expect(WorldClockMath.offsetDifference(newYork, relativeTo: beijing, at: afterSpring) == -12 * 3600, "NY is 12h behind Beijing after DST")
expect(WorldClockMath.differenceLabel(seconds: -13 * 3600) == "−13小时", "difference label −13小时")
expect(WorldClockMath.differenceLabel(seconds: 9000) == "+2小时30分", "difference label with minutes")
expect(WorldClockMath.differenceLabel(seconds: 0) == "相同", "same zone label")
expect(WorldClockMath.differenceLabel(seconds: 2 * 3600 + 30 * 60) == "+2小时30分", "India vs Beijing style label")
expect(WorldClockMath.offsetDifference(kolkata, relativeTo: beijing, at: afterSpring) == -(2 * 3600 + 30 * 60), "Kolkata is 2:30 behind Beijing")

// 2026-11-01 US fall-back (06:00 UTC).
let beforeFall = instant("2026-11-01T05:30:00Z")
let afterFall = instant("2026-11-01T06:30:00Z")
expect(WorldClockMath.offsetDifference(newYork, relativeTo: beijing, at: beforeFall) == -12 * 3600, "NY −12h before fall back")
expect(WorldClockMath.offsetDifference(newYork, relativeTo: beijing, at: afterFall) == -13 * 3600, "NY −13h after fall back")

// Day offsets: 2026-03-08 06:30Z is Beijing 14:30 Mar 8, NY 01:30 Mar 8 → same day.
expect(WorldClockMath.dayOffset(of: beforeSpring, in: newYork, relativeTo: beijing) == 0, "same day in NY and Beijing")
// 2026-03-08 20:00Z is Beijing 04:00 Mar 9, NY 16:00 Mar 8 → NY is 昨天.
let evening = instant("2026-03-08T20:00:00Z")
expect(WorldClockMath.dayOffset(of: evening, in: newYork, relativeTo: beijing) == -1, "NY is yesterday relative to Beijing")
expect(WorldClockMath.dayOffset(of: evening, in: beijing, relativeTo: newYork) == 1, "Beijing is tomorrow relative to NY")
// Month boundary: 2026-02-28 20:00Z → Beijing Mar 1 04:00, London Feb 28 20:00.
expect(WorldClockMath.dayOffset(of: instant("2026-02-28T20:00:00Z"), in: london, relativeTo: beijing) == -1, "day offset across month boundary")
// Year boundary.
expect(WorldClockMath.dayOffset(of: instant("2026-12-31T20:00:00Z"), in: newYork, relativeTo: beijing) == -1, "day offset across year boundary")
expect(WorldClockMath.dayOffsetLabel(-1) == "昨天" && WorldClockMath.dayOffsetLabel(1) == "明天", "day offset labels")

// Converter: 15:00 Beijing on 2026-03-08 → NY 02:00 (EST, before 07:00Z switch) — 07:00Z is exactly the switch.
let beijing1500 = WorldClockMath.date(atMinuteOfDay: 15 * 60, sameDayAs: beforeSpring, in: beijing)
expect(beijing1500 == instant("2026-03-08T07:00:00Z"), "15:00 Beijing on Mar 8 = 07:00Z")
expect(WorldClockMath.minuteOfDay(of: beijing1500, in: newYork) == 3 * 60, "…which is 03:00 EDT in NY (clock jumped at 07:00Z)")
// Converter on a NY DST day using NY as the main zone: 03:30 exists, 02:30 doesn't.
let nyDay = instant("2026-03-08T12:00:00Z")
let ny0330 = WorldClockMath.date(atMinuteOfDay: 3 * 60 + 30, sameDayAs: nyDay, in: newYork)
expect(WorldClockMath.minuteOfDay(of: ny0330, in: newYork) == 3 * 60 + 30, "03:30 on spring-forward day stays 03:30")
expect(ny0330 == instant("2026-03-08T07:30:00Z"), "03:30 EDT = 07:30Z")
// Fall-back day: 18:00 NY on Nov 1 = 23:00Z (EST).
let ny1800 = WorldClockMath.date(atMinuteOfDay: 18 * 60, sameDayAs: instant("2026-11-01T15:00:00Z"), in: newYork)
expect(ny1800 == instant("2026-11-01T23:00:00Z"), "18:00 on fall-back day = 23:00Z")

// MARK: Lunar calendar

let newYear2026 = LunarCalendar.lunarDate(year: 2026, month: 2, day: 17)
expect(newYear2026.month == 1 && newYear2026.day == 1 && !newYear2026.isLeapMonth, "2026-02-17 is 正月初一 (got \(newYear2026.monthName)\(newYear2026.dayName))")
expect(newYear2026.yearName == "丙午" && newYear2026.zodiacName == "马", "2026 is 丙午马年 (got \(newYear2026.yearName)\(newYear2026.zodiacName))")
let newYear2025 = LunarCalendar.lunarDate(year: 2025, month: 1, day: 29)
expect(newYear2025.month == 1 && newYear2025.day == 1 && newYear2025.yearName == "乙巳", "2025-01-29 is 乙巳年正月初一")
let eve2026 = LunarCalendar.lunarDate(year: 2026, month: 2, day: 16)
expect(eve2026.month == 12 && eve2026.yearName == "乙巳", "2026-02-16 is 乙巳年腊月 (除夕)")
let midAutumn2025 = LunarCalendar.lunarDate(year: 2025, month: 10, day: 6)
expect(midAutumn2025.month == 8 && midAutumn2025.day == 15, "2025-10-06 is 八月十五 中秋 (got \(midAutumn2025.monthName)\(midAutumn2025.dayName))")
// 2025 has a leap sixth month starting 2025-07-25.
let leap = LunarCalendar.lunarDate(year: 2025, month: 7, day: 25)
expect(leap.isLeapMonth && leap.month == 6 && leap.day == 1, "2025-07-25 is 闰六月初一 (got \(leap.monthName)\(leap.dayName))")
expect(leap.monthName == "闰六月", "leap month name")
expect(LunarDate(cycleYear: 43, month: 8, day: 4, isLeapMonth: false).dayName == "初四", "初四")
expect(LunarDate(cycleYear: 43, month: 8, day: 10, isLeapMonth: false).dayName == "初十", "初十")
expect(LunarDate(cycleYear: 43, month: 8, day: 15, isLeapMonth: false).dayName == "十五", "十五")
expect(LunarDate(cycleYear: 43, month: 8, day: 20, isLeapMonth: false).dayName == "二十", "二十")
expect(LunarDate(cycleYear: 43, month: 8, day: 23, isLeapMonth: false).dayName == "廿三", "廿三")
expect(LunarDate(cycleYear: 43, month: 8, day: 30, isLeapMonth: false).dayName == "三十", "三十")
expect(LunarDate(cycleYear: 43, month: 11, day: 1, isLeapMonth: false).cellLabel == "冬月", "month label on day one")

// MARK: Solar terms (published instants, UTC)

func minutesBetween(_ a: Date, _ b: Date) -> Double { abs(a.timeIntervalSince(b)) / 60 }
func term(_ name: String, _ year: Int) -> Date? { SolarTerms.terms(in: year).first { $0.name == name }?.date }

let published: [(String, Int, String)] = [
    ("春分", 2026, "2026-03-20T14:46:00Z"),
    ("夏至", 2026, "2026-06-21T08:24:00Z"),
    ("秋分", 2026, "2026-09-23T00:05:00Z"),
    ("冬至", 2026, "2026-12-21T20:50:00Z"),
    ("春分", 2025, "2025-03-20T09:01:00Z"),
    ("冬至", 2025, "2025-12-21T15:03:00Z"),
    ("立春", 2026, "2026-02-03T20:02:00Z"),
    ("立春", 2024, "2024-02-04T08:27:00Z"),
]
for (name, year, expected) in published {
    guard let computed = term(name, year) else { expect(false, "\(name) \(year) missing"); continue }
    let error = minutesBetween(computed, instant(expected))
    expect(error < 20, "\(name) \(year) within 20 min (off by \(Int(error)) min)")
}
expect(SolarTerms.terms(in: 2026).count == 24, "24 terms per year")
expect(Set(SolarTerms.terms(in: 2026).map(\.name)).count == 24, "all term names distinct")
expect(SolarTerms.termName(year: 2026, month: 2, day: 4) == "立春", "立春 on Feb 4 2026 Beijing")
expect(SolarTerms.termName(year: 2026, month: 12, day: 22) == "冬至", "冬至 on Dec 22 2026 Beijing")
expect(SolarTerms.termName(year: 2026, month: 9, day: 23) == "秋分", "秋分 on Sep 23 2026 Beijing")
expect(SolarTerms.termName(year: 2026, month: 9, day: 24) == nil, "no term on Sep 24")

// MARK: Work schedule

let schedule = WorkSchedule()
// 2026-09-25 is a Friday. Beijing = UTC+8.
expect(schedule.state(at: instant("2026-09-25T02:00:00Z")) == .working, "Fri 10:00 working")
expect(schedule.state(at: instant("2026-09-25T04:30:00Z")) == .lunch, "Fri 12:30 lunch")
expect(schedule.state(at: instant("2026-09-25T11:00:00Z")) == .offWork, "Fri 19:00 off work")
expect(schedule.state(at: instant("2026-09-25T16:00:00Z")) == .night, "Sat 00:00 night")
expect(schedule.state(at: instant("2026-09-26T02:00:00Z")) == .weekend, "Sat 10:00 weekend")
let status = schedule.status(at: instant("2026-09-25T08:00:00Z")) // Fri 16:00
expect(status.state == .working && status.nextChange == instant("2026-09-25T10:00:00Z"), "Fri 16:00 → off at 18:00")
let fridayNight = schedule.status(at: instant("2026-09-25T14:00:00Z")) // Fri 22:00 off → night at 23:00
expect(fridayNight.nextChange == instant("2026-09-25T15:00:00Z"), "Fri 22:00 → night at 23:00")
expect(WorkSchedule.durationLabel(from: instant("2026-09-25T08:00:00Z"), to: instant("2026-09-25T10:15:00Z")) == "2小时15分", "duration label")
expect(WorkSchedule.contains(30, from: 23 * 60, to: 7 * 60), "wrap-around range contains 00:30")
expect(!WorkSchedule.contains(12 * 60, from: 23 * 60, to: 7 * 60), "wrap-around range excludes noon")

// Quiet hours
let quiet = QuietHours(isEnabled: true, start: 22 * 60, end: 8 * 60)
expect(quiet.contains(instant("2026-09-25T15:00:00Z"), in: beijing), "23:00 Beijing is quiet")
expect(!quiet.contains(instant("2026-09-25T02:00:00Z"), in: beijing), "10:00 Beijing is not quiet")
expect(!QuietHours(isEnabled: false).contains(instant("2026-09-25T15:00:00Z"), in: beijing), "disabled quiet hours never mute")

// MARK: Alarms

// One-shot 07:00 Beijing, asked at Fri 2026-09-25 10:00 Beijing → Sat 07:00 Beijing = Fri 23:00Z.
let wakeUp = Alarm(hour: 7, minute: 0, timeZoneIdentifier: "Asia/Shanghai")
expect(wakeUp.nextFireDate(after: instant("2026-09-25T02:00:00Z")) == instant("2026-09-25T23:00:00Z"), "one-shot rolls to tomorrow")
expect(wakeUp.nextFireDate(after: instant("2026-09-25T22:00:00Z")) == instant("2026-09-25T23:00:00Z"), "one-shot later today")
// Weekday alarm 09:00 Beijing, asked Fri 10:00 → next Monday 09:00 = Mon 01:00Z (2026-09-28).
let weekdays = Alarm(hour: 9, minute: 0, timeZoneIdentifier: "Asia/Shanghai", repeatDays: [2, 3, 4, 5, 6])
expect(weekdays.nextFireDate(after: instant("2026-09-25T02:00:00Z")) == instant("2026-09-28T01:00:00Z"), "weekday alarm skips weekend")
// NY 09:00 alarm checked from Beijing's perspective: Fri 2026-09-25 10:00 Beijing = Thu 22:00 NY → Fri 09:00 NY = 13:00Z.
let nyAlarm = Alarm(hour: 9, minute: 0, timeZoneIdentifier: "America/New_York", repeatDays: [6])
expect(nyAlarm.nextFireDate(after: instant("2026-09-25T02:00:00Z")) == instant("2026-09-25T13:00:00Z"), "Friday alarm in NY zone uses NY weekday")
// DST: NY 09:00 daily across spring forward: Mar 7 09:00 EST = 14:00Z, Mar 8 09:00 EDT = 13:00Z.
let daily = Alarm(hour: 9, minute: 0, timeZoneIdentifier: "America/New_York", repeatDays: Set(1...7))
expect(daily.nextFireDate(after: instant("2026-03-07T12:00:00Z")) == instant("2026-03-07T14:00:00Z"), "daily NY alarm before DST")
expect(daily.nextFireDate(after: instant("2026-03-07T14:00:00Z")) == instant("2026-03-08T13:00:00Z"), "daily NY alarm after DST shifts UTC hour")
// Nonexistent wall time 02:30 on spring-forward day rings at the next valid time (03:00 EDT = 07:00Z).
let skipped = Alarm(hour: 2, minute: 30, timeZoneIdentifier: "America/New_York")
let skippedFire = skipped.nextFireDate(after: instant("2026-03-08T05:00:00Z"))
expect(skippedFire != nil && skippedFire! >= instant("2026-03-08T07:00:00Z") && skippedFire! <= instant("2026-03-08T07:30:00Z"), "skipped 02:30 rings right after the jump (got \(String(describing: skippedFire)))")
expect(weekdays.repeatLabel == "工作日" && daily.repeatLabel == "每天" && wakeUp.repeatLabel == "仅一次", "repeat labels")
expect(Alarm(hour: 1, minute: 0, timeZoneIdentifier: "UTC", repeatDays: [2, 4, 6]).repeatLabel == "周一 三 五", "custom repeat label")

print(failures == 0 ? "OK — \(checks) checks passed" : "\(failures) of \(checks) checks FAILED")
exit(failures == 0 ? 0 : 1)
