import AppKit
import ServiceManagement

/// Launch at login through `SMAppService.mainApp` (replaces the old per-user LaunchAgent).
@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    private static let didAutoRegisterKey = "didAutoRegisterLoginItem"

    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var lastError: String?

    private init() {
        refresh()
    }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    var subtitle: String {
        if lastError != nil { return "失败" }
        switch status {
        case .enabled: return "开"
        case .requiresApproval: return "待批准"
        case .notFound: return "不可用"
        default: return "关"
        }
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool, openSettingsIfApprovalNeeded: Bool = true) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
        if openSettingsIfApprovalNeeded && status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// The installer no longer creates a LaunchAgent, so the installed copy turns itself on once.
    /// Builds run from other folders (Xcode, build/) never register, to keep stray copies out of Login Items.
    func registerOnFirstInstalledLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.didAutoRegisterKey) else { return }
        let path = Bundle.main.bundleURL.deletingLastPathComponent().path
        let installFolders = ["/Applications", NSHomeDirectory() + "/Applications"]
        guard installFolders.contains(path) else { return }
        defaults.set(true, forKey: Self.didAutoRegisterKey)
        if status != .enabled {
            setEnabled(true, openSettingsIfApprovalNeeded: false)
        }
    }
}
