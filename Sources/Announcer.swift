import AppKit
import AVFoundation

/// Plays the chosen announcement sound and speaks Chinese text. Shared by the hourly
/// announcement and alarms so they sound the same.
@MainActor
final class Announcer {
    static let shared = Announcer()

    private let speech = AVSpeechSynthesizer()

    func playSound(for settings: ClockSettings) {
        switch settings.soundName {
        case "无": return
        case "自定义…":
            guard !settings.customSoundPath.isEmpty else { return }
            NSSound(contentsOfFile: settings.customSoundPath, byReference: true)?.play()
        case "系统声音": NSSound(named: "Glass")?.play()
        default: NSSound(named: settings.soundName)?.play()
        }
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        speech.speak(utterance)
    }

    /// "8点整", "8点15分"
    static func spokenTime(hour: Int, minute: Int) -> String {
        "\(hour)点\(minute == 0 ? "整" : "\(minute)分")"
    }
}
