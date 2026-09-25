import Foundation

/// The 24 solar terms (二十四节气), computed offline from the Sun's apparent ecliptic longitude.
///
/// Uses the low-accuracy solar position from Meeus, *Astronomical Algorithms* ch. 25 (≈0.01°,
/// i.e. within about 15 minutes of the true instant). The term's calendar day is taken in Beijing
/// time, so only a term falling within minutes of Beijing midnight could land on the wrong day.
enum SolarTerms {
    struct Term: Equatable {
        let name: String
        let date: Date
    }

    /// Names indexed by longitude / 15°, starting at 春分 (0°).
    static let names = [
        "春分", "清明", "谷雨", "立夏", "小满", "芒种", "夏至", "小暑", "大暑", "立秋", "处暑", "白露",
        "秋分", "寒露", "霜降", "立冬", "小雪", "大雪", "冬至", "小寒", "大寒", "立春", "雨水", "惊蛰"
    ]

    private static var cache: [Int: [Term]] = [:]
    private static let lock = NSLock()

    /// All 24 terms whose instant falls in Gregorian `year` (UTC), sorted by date.
    static func terms(in year: Int) -> [Term] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[year] { return cached }

        var result: [Term] = []
        // 小寒 (285°) in early January through 冬至 (270°) in late December.
        for index in 0..<24 {
            let longitude = Double((19 + index) % 24) * 15
            // Rough guess: 小寒 ≈ Jan 5, then ~15.22 days per term.
            let guess = julianDay(year: year, month: 1, day: 5.5) + Double(index) * 15.2184
            let jde = solve(longitude: longitude, near: guess)
            result.append(Term(name: names[Int(longitude / 15)], date: date(fromJDE: jde)))
        }
        result.sort { $0.date < $1.date }
        cache[year] = result
        return result
    }

    /// Term name for the Beijing calendar day `year-month-day`, if one begins that day.
    static func termName(year: Int, month: Int, day: Int) -> String? {
        var beijing = Calendar(identifier: .gregorian)
        beijing.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        for term in terms(in: year) {
            let parts = beijing.dateComponents([.year, .month, .day], from: term.date)
            if parts.year == year && parts.month == month && parts.day == day { return term.name }
        }
        return nil
    }

    // MARK: - Astronomy

    /// Apparent geocentric ecliptic longitude of the Sun in degrees, for a Julian Ephemeris Day.
    static func apparentSolarLongitude(jde: Double) -> Double {
        let t = (jde - 2_451_545.0) / 36_525
        let l0 = 280.46646 + 36_000.76983 * t + 0.0003032 * t * t
        let m = radians(357.52911 + 35_999.05029 * t - 0.0001537 * t * t)
        let center = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(m)
            + (0.019993 - 0.000101 * t) * sin(2 * m)
            + 0.000289 * sin(3 * m)
        let omega = radians(125.04 - 1_934.136 * t)
        return normalize(l0 + center - 0.00569 - 0.00478 * sin(omega))
    }

    /// Newton iteration: the Sun moves ~360° per 365.2422 days.
    private static func solve(longitude target: Double, near guess: Double) -> Double {
        var jde = guess
        for _ in 0..<8 {
            var delta = target - apparentSolarLongitude(jde: jde)
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            jde += delta * 365.2422 / 360
            if abs(delta) < 1e-7 { break }
        }
        return jde
    }

    private static func julianDay(year: Int, month: Int, day: Double) -> Double {
        var y = Double(year)
        var m = Double(month)
        if m <= 2 {
            y -= 1
            m += 12
        }
        let a = (y / 100).rounded(.down)
        let b = 2 - a + (a / 4).rounded(.down)
        return (365.25 * (y + 4716)).rounded(.down) + (30.6001 * (m + 1)).rounded(.down) + day + b - 1524.5
    }

    /// JDE (Terrestrial Time) → Date (UT), subtracting ΔT.
    private static func date(fromJDE jde: Double) -> Date {
        let unixSeconds = (jde - 2_440_587.5) * 86_400
        let year = 1970 + unixSeconds / 31_556_952
        return Date(timeIntervalSince1970: unixSeconds - deltaT(year: year))
    }

    /// ΔT = TT − UT in seconds (Espenak & Meeus polynomial for 2005–2050).
    private static func deltaT(year: Double) -> Double {
        let t = year - 2000
        return 62.92 + 0.32217 * t + 0.005589 * t * t
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    private static func normalize(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}
