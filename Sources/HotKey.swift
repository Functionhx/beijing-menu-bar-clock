import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A key combination for the global "show panel" shortcut, stored in Carbon terms.
struct HotKeySetting: Codable, Equatable {
    var isEnabled = true
    var keyCode = UInt32(kVK_ANSI_B)
    var carbonModifiers = UInt32(cmdKey | optionKey)
    var keyName = "B"

    /// "⌥⌘B", in the conventional ⌃⌥⇧⌘ order.
    var displayName: String {
        var text = ""
        if carbonModifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyName
    }

    /// Builds a setting from a key-down event, or nil if it has no ⌘/⌥/⌃ (plain keys would hijack typing).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        keyCode = UInt32(event.keyCode)
        carbonModifiers = modifiers
        keyName = Self.name(forKeyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
    }

    init() {}

    /// F-key codes are not contiguous, so they are looked up by position.
    private static let functionKeys = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
    ]

    private static func name(forKeyCode keyCode: UInt16, characters: String?) -> String {
        if let index = functionKeys.firstIndex(of: Int(keyCode)) { return "F\(index + 1)" }
        switch Int(keyCode) {
        case kVK_Space: return "空格"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            return (characters ?? "?").uppercased()
        }
    }
}

/// System-wide shortcut via Carbon `RegisterEventHotKey`, which needs no Accessibility permission.
@MainActor
final class GlobalHotKey: ObservableObject {
    static let shared = GlobalHotKey()

    /// True when the last registration failed, usually because another app owns the combination.
    @Published private(set) var registrationFailed = false
    var action: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func apply(_ setting: HotKeySetting) {
        unregister()
        guard setting.isEnabled else {
            registrationFailed = false
            return
        }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x424D_4348), id: 1) // "BMCH"
        let status = RegisterEventHotKey(
            setting.keyCode,
            setting.carbonModifiers,
            id,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        registrationFailed = status != noErr
    }

    /// Temporarily releases the shortcut, e.g. while recording a new one.
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in
            Task { @MainActor in GlobalHotKey.shared.action?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}

/// Click, then press a new combination. Esc cancels.
struct HotKeyRecorder: View {
    @Binding var setting: HotKeySetting
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? "请按下快捷键…" : setting.displayName)
                    .font(.system(size: 12, weight: .medium).monospaced())
                    .frame(minWidth: 96)
            }
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        isRecording = true
        hint = "需包含 ⌘、⌥ 或 ⌃ · Esc 取消"
        GlobalHotKey.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            guard var recorded = HotKeySetting(event: event) else {
                NSSound.beep()
                return nil
            }
            recorded.isEnabled = true
            setting = recorded
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if isRecording {
            isRecording = false
            hint = nil
            GlobalHotKey.shared.apply(setting)
        }
    }
}
