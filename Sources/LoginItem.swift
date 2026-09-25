import AppKit
import ServiceManagement

/// Launch at login through a per-user LaunchAgent in ~/Library/LaunchAgents (install.sh writes the same file).
/// SMAppService.mainApp registrations didn't survive a reboot for these ad-hoc signed builds (no Team ID),
/// while a plain LaunchAgent does.
@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    @Published private(set) var isEnabled = false
    @Published private(set) var lastError: String?

    private init() {
        refresh()
        removeServiceManagementRegistration()
    }

    var subtitle: String { isEnabled ? "开" : "关" }

    /// Nil for unbundled test builds, which must never touch the installed app's LaunchAgent.
    private var label: String? { Bundle.main.bundleIdentifier }

    private var agentURL: URL? {
        label.map {
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\($0).plist")
        }
    }

    func refresh() {
        isEnabled = agentURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        guard let label, let agentURL else {
            lastError = "仅安装版可用"
            return
        }
        do {
            if enabled {
                try FileManager.default.createDirectory(
                    at: agentURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let agent: [String: Any] = [
                    "Label": label,
                    "ProgramArguments": [Bundle.main.executablePath ?? ""],
                    "RunAtLoad": true,
                    "ProcessType": "Interactive",
                    "AssociatedBundleIdentifiers": [label]
                ]
                let data = try PropertyListSerialization.data(fromPropertyList: agent, format: .xml, options: 0)
                try data.write(to: agentURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: agentURL.path) {
                // Only the file goes: booting the job out would also quit this app when launchd started it.
                try FileManager.default.removeItem(at: agentURL)
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// The previous build registered through SMAppService; drop that record so the app isn't listed twice.
    private func removeServiceManagementRegistration() {
        guard label != nil else { return }
        let service = SMAppService.mainApp
        guard service.status == .enabled || service.status == .requiresApproval else { return }
        service.unregister { _ in }
    }
}
