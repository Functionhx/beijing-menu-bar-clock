import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    private let settings = ClockSettings.shared
    private let speech = AVSpeechSynthesizer()
    private var timer: Timer?
    private var settingsWindow: NSWindow?
    private var lastAnnouncementMinute = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureMenu()
        NotificationCenter.default.addObserver(
            forName: ClockSettings.changed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateClock() }
        }
        updateClock()
        startTimer()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.toolTip = "北京时间"
        button.imagePosition = .noImage
        statusItem.menu = menu
    }

    private func configureMenu() {
        menu.delegate = self

        let options = NSMenuItem(title: "时钟选项…", action: #selector(showSettings), keyEquivalent: ",")
        options.target = self
        menu.addItem(options)

        let refresh = NSMenuItem(title: "刷新", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出北京时间", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateClock() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func updateClock() {
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone

        var parts: [String] = []
        if settings.showDate {
            formatter.dateFormat = "M月d日"
            parts.append(formatter.string(from: now))
        }
        if settings.showWeekday {
            formatter.dateFormat = "EEE"
            parts.append(formatter.string(from: now))
        }

        formatter.dateFormat = settings.showSeconds ? "HH:mm:ss" : "HH:mm"
        var time = formatter.string(from: now)
        let second = Calendar(identifier: .gregorian).dateComponents(in: timeZone, from: now).second ?? 0
        if settings.flashSeparators && second.isMultiple(of: 2) == false {
            time = time.replacingOccurrences(of: ":", with: " ")
        }
        parts.append(time)
        statusItem.button?.title = parts.joined(separator: " ")

        announceIfNeeded(now)
    }

    private func announceIfNeeded(_ date: Date) {
        guard settings.announceTime else { return }
        let calendar = Calendar(identifier: .gregorian)
        let values = calendar.dateComponents(in: timeZone, from: date)
        guard values.second == 0, let minute = values.minute, let hour = values.hour else { return }

        let shouldAnnounce: Bool
        switch settings.announceInterval {
        case "每刻钟": shouldAnnounce = minute.isMultiple(of: 15)
        case "每半小时": shouldAnnounce = minute.isMultiple(of: 30)
        default: shouldAnnounce = minute == 0
        }
        guard shouldAnnounce else { return }

        let key = "\(values.year ?? 0)-\(values.month ?? 0)-\(values.day ?? 0)-\(hour)-\(minute)"
        guard key != lastAnnouncementMinute else { return }
        lastAnnouncementMinute = key

        playAnnouncementSound()
        let utterance = AVSpeechUtterance(string: "现在是北京时间\(hour)点\(minute == 0 ? "整" : "\(minute)分")")
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        speech.speak(utterance)
    }

    private func playAnnouncementSound() {
        switch settings.soundName {
        case "无": return
        case "自定义…":
            guard !settings.customSoundPath.isEmpty else { return }
            NSSound(contentsOfFile: settings.customSoundPath, byReference: true)?.play()
        case "系统声音": NSSound(named: "Glass")?.play()
        default: NSSound(named: settings.soundName)?.play()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateClock()
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings) { [weak self] in
                self?.settingsWindow?.close()
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "时钟选项"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func refreshNow() {
        updateClock()
        startTimer()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

@main
@MainActor
struct BeijingMenuBarClockApp {
    private static let appDelegate = AppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.delegate = appDelegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
