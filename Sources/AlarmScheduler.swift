import AppKit
import Combine
import UserNotifications

/// Rings alarms with one timer set for the earliest upcoming alarm. The timer is rebuilt whenever
/// alarms change, the Mac wakes, or the system clock / time zone changes — no polling.
@MainActor
final class AlarmScheduler: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = AlarmScheduler()

    /// Alarms rung this late after their time still ring; older ones (slept through) are reported as missed.
    private static let lateness: TimeInterval = 10 * 60

    @Published private(set) var notificationsDenied = false

    private let settings = UltraSettings.shared
    private var timer: Timer?
    private var lastEvaluated = Date()
    private var alarmsSubscription: AnyCancellable?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    /// UserNotifications crashes in processes without a bundle identifier (e.g. command-line harnesses).
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    func start() {
        guard alarmsSubscription == nil else { return }
        lastEvaluated = Date()
        if canNotify {
            UNUserNotificationCenter.current().delegate = self
            refreshAuthorization()
        }

        // @Published emits on willSet, so schedule from the emitted value. Edits count from now,
        // so adding or re-enabling an alarm never rings (or reports as missed) an earlier occurrence.
        alarmsSubscription = settings.$alarms.dropFirst().sink { [weak self] alarms in
            self?.lastEvaluated = Date()
            self?.schedule(alarms)
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)
        observe(.default, .NSSystemClockDidChange)
        observe(.default, .NSSystemTimeZoneDidChange)
        schedule(settings.alarms)
    }

    /// Asks for notification permission the first time the user creates an alarm.
    func requestAuthorizationIfNeeded() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            Task { @MainActor in self?.refreshAuthorization() }
        }
    }

    func refreshAuthorization() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] notificationSettings in
            let denied = notificationSettings.authorizationStatus == .denied
            Task { @MainActor in self?.notificationsDenied = denied }
        }
    }

    // MARK: Scheduling

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        observers.append((center, token))
    }

    private func schedule(_ alarms: [Alarm]) {
        timer?.invalidate()
        timer = nil
        let next = alarms.filter(\.isEnabled).compactMap { $0.nextFireDate(after: lastEvaluated) }.min()
        guard let next else { return }
        let timer = Timer(fire: next.addingTimeInterval(0.05), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Rings every alarm due since the last evaluation, then re-arms the timer.
    private func evaluate(now: Date = Date()) {
        var alarms = settings.alarms
        var changed = false
        for index in alarms.indices where alarms[index].isEnabled {
            let alarm = alarms[index]
            guard let due = alarm.nextFireDate(after: lastEvaluated), due <= now else { continue }
            if now.timeIntervalSince(due) <= Self.lateness {
                ring(alarm)
            } else {
                notify(title: "错过的闹钟：\(alarm.displayLabel)", body: "\(alarm.timeLabel) · 当时 Mac 处于睡眠状态", sound: false)
            }
            if alarm.repeatDays.isEmpty {
                alarms[index].isEnabled = false
                changed = true
            }
        }
        lastEvaluated = now
        if changed {
            settings.alarms = alarms // re-schedules through the subscription
        } else {
            schedule(alarms)
        }
    }

    private func ring(_ alarm: Alarm) {
        let zoneTitle = TimeZoneSearch.entry(for: alarm.timeZoneIdentifier).title
        notify(
            title: "⏰ \(alarm.displayLabel)",
            body: "\(zoneTitle) \(alarm.timeLabel) · \(alarm.repeatLabel)",
            sound: !alarm.speaks
        )
        if alarm.speaks {
            Announcer.shared.playSound(for: ClockSettings.shared)
            Announcer.shared.speak("\(alarm.displayLabel)，现在是\(zoneTitle)时间\(Announcer.spokenTime(hour: alarm.hour, minute: alarm.minute))")
        }
    }

    private func notify(title: String, body: String, sound: Bool) {
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound ? .default : nil
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Menu bar apps count as "active"; show the banner anyway.
        completionHandler([.banner, .list, .sound])
    }
}
