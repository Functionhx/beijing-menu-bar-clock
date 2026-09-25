import AppKit
import Sparkle

/// Thin wrapper around Sparkle. Feed URL, public key and automatic checks come from Info.plist
/// (SUFeedURL / SUPublicEDKey / SUEnableAutomaticChecks), which are filled in from Config/Branch.xcconfig.
@MainActor
final class Updater: NSObject {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController

    private override init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: Updater.isConfigured,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    /// Unsigned local builds without a public key must not start Sparkle, it would refuse every update anyway.
    static var isConfigured: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !key.isEmpty
    }

    func start() {
        _ = controller
    }

    @objc func checkForUpdates(_ sender: Any?) {
        guard Self.isConfigured else {
            let alert = NSAlert()
            alert.messageText = "此版本未启用自动更新"
            alert.informativeText = "这是本地开发构建，没有配置更新签名公钥。请使用 scripts/release.sh 打包的正式版本。"
            alert.addButton(withTitle: "好")
            alert.runModal()
            return
        }
        controller.checkForUpdates(sender)
    }
}
