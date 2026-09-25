import AppKit
import UserNotifications

/// Saved important dates plus their reminder notifications.
@MainActor
final class ImportantDateStore: NSObject, ObservableObject {
    static let shared = ImportantDateStore()

    private static let key = "importantDates"
    private static let notificationPrefix = "important-"

    @Published private(set) var items: [ImportantDate]
    /// True once the user has turned notifications off for this app.
    @Published private(set) var notificationsDenied = false

    private let defaults = UserDefaults.standard
    private var started = false

    /// UserNotifications needs a bundle; unbundled test builds skip reminders.
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    private override init() {
        if let data = defaults.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode([ImportantDate].self, from: data) {
            items = stored
        } else {
            items = []
        }
        super.init()
    }

    /// Starts delivering reminders: shows them while the app is running and reschedules when the day,
    /// the clock's time zone, or the system clock changes.
    func start() {
        guard canNotify, !started else { return }
        started = true
        UNUserNotificationCenter.current().delegate = self
        let center = NotificationCenter.default
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange, ClockSettings.changed] {
            center.addObserver(self, selector: #selector(environmentChanged), name: name, object: nil)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(environmentChanged), name: NSWorkspace.didWakeNotification, object: nil
        )
        refreshAuthorization()
        scheduleReminders()
    }

    @objc private func environmentChanged() {
        scheduleReminders()
    }

    // MARK: Editing

    func save(_ item: ImportantDate) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        persist()
        if !item.reminderDays.isEmpty || (item.isPeriod && item.remindsAtEnd) {
            requestAuthorization()
        }
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.key)
        }
        scheduleReminders()
    }

    // MARK: Queries

    var timeZone: TimeZone { ClockSettings.shared.effectiveTimeZone }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    var today: DayStamp { DayStamp(Date(), calendar: calendar) }

    struct Entry: Identifiable, Equatable {
        let item: ImportantDate
        let occurrence: ImportantDate.Occurrence
        var id: UUID { item.id }
    }

    /// In-progress and upcoming dates first (soonest first), then one-off dates that have passed (latest first).
    func upcoming(from day: DayStamp) -> [Entry] {
        var future: [Entry] = []
        var past: [Entry] = []
        for item in items {
            if let occurrence = item.occurrence(onOrAfter: day) {
                future.append(Entry(item: item, occurrence: occurrence))
            } else if let occurrence = item.lastOccurrence(before: day) {
                past.append(Entry(item: item, occurrence: occurrence))
            }
        }
        future.sort { ($0.occurrence.start, $0.item.title) < ($1.occurrence.start, $1.item.title) }
        past.sort { $0.occurrence.end > $1.occurrence.end }
        return future + past
    }

    /// Everything happening on each day of the given range, keyed by day.
    func entriesByDay(from first: DayStamp, through last: DayStamp) -> [DayStamp: [Entry]] {
        var result: [DayStamp: [Entry]] = [:]
        for item in items {
            for occurrence in item.occurrences(from: first, through: last) {
                var day = max(occurrence.start, first)
                let end = min(occurrence.end, last)
                while day <= end {
                    result[day, default: []].append(Entry(item: item, occurrence: occurrence))
                    day = day.adding(days: 1)
                }
            }
        }
        return result
    }

    // MARK: Reminders

    private func refreshAuthorization() {
        guard canNotify else { return }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsDenied = settings.authorizationStatus == .denied
        }
    }

    private func requestAuthorization() {
        guard canNotify else { return }
        Task {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
            notificationsDenied = !granted
            if granted { scheduleReminders() }
        }
    }

    /// Replaces all pending reminders with the ones for each item's next occurrence.
    func scheduleReminders() {
        guard canNotify else { return }
        let requests = pendingRequests(now: Date())
        Task {
            let center = UNUserNotificationCenter.current()
            let stale = await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { $0.hasPrefix(Self.notificationPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            for request in requests {
                try? await center.add(request)
            }
        }
    }

    private func pendingRequests(now: Date) -> [UNNotificationRequest] {
        let calendar = self.calendar
        let today = DayStamp(now, calendar: calendar)
        var requests: [UNNotificationRequest] = []

        for item in items {
            guard let occurrence = item.occurrence(onOrAfter: today) else { continue }
            var fires: [(key: String, day: DayStamp, body: String)] = item.reminderDays.map { daysBefore in
                let day = occurrence.start.adding(days: -daysBefore)
                return ("\(daysBefore)", day, reminderBody(item, occurrence, daysBefore: daysBefore))
            }
            if item.isPeriod && item.remindsAtEnd && occurrence.end != occurrence.start {
                fires.append(("end", occurrence.end, "今天截止 · \(item.dateLabel(for: occurrence))"))
            }

            for fire in fires {
                var components = DateComponents(
                    calendar: calendar,
                    timeZone: calendar.timeZone,
                    year: fire.day.year,
                    month: fire.day.month,
                    day: fire.day.day,
                    hour: item.reminderMinute / 60,
                    minute: item.reminderMinute % 60
                )
                guard let date = calendar.date(from: components), date > now else { continue }
                components.calendar = calendar
                let content = UNMutableNotificationContent()
                content.title = "\(Self.emoji(for: item.kind)) \(item.title)"
                content.body = fire.body
                content.sound = .default
                requests.append(UNNotificationRequest(
                    identifier: "\(Self.notificationPrefix)\(item.id.uuidString)-\(fire.key)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                ))
            }
        }
        return requests
    }

    private func reminderBody(_ item: ImportantDate, _ occurrence: ImportantDate.Occurrence, daysBefore: Int) -> String {
        let when: String
        switch daysBefore {
        case 0: when = item.isPeriod ? "今天开始" : "就是今天"
        case 1: when = "明天"
        default: when = "还有 \(daysBefore) 天"
        }
        var details = item.dateLabel(for: occurrence)
        if let age = item.age(at: occurrence) { details += " · \(age)岁" }
        if let lunar = item.lunarLabel { details += " · \(lunar)" }
        return "\(when) · \(details)"
    }

    static func emoji(for kind: ImportantDate.Kind) -> String {
        switch kind {
        case .birthday: return "🎂"
        case .anniversary: return "❤️"
        case .exam: return "📝"
        case .deadline: return "⏰"
        case .other: return "⭐️"
        }
    }
}

extension ImportantDateStore: UNUserNotificationCenterDelegate {
    /// The app is always running in the menu bar, so show reminders as banners even in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
