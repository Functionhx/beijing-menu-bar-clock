import AppKit
import Foundation

struct ManagedTimeZoneApp: Codable, Identifiable, Equatable {
    var id: UUID
    var bundleIdentifier: String
    var displayName: String
    var applicationPath: String
    var timeZoneIdentifier: String

    init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        displayName: String,
        applicationPath: String,
        timeZoneIdentifier: String = "Asia/Shanghai"
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.applicationPath = applicationPath
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    var applicationURL: URL {
        if let installedURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return installedURL
        }
        return URL(fileURLWithPath: applicationPath)
    }
}
