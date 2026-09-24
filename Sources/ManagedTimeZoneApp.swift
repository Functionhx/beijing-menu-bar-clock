import AppKit
import Foundation

struct ManagedTimeZoneApp: Codable, Identifiable, Equatable {
    var id: UUID
    var bundleIdentifier: String
    var displayName: String
    var applicationPath: String
    var timeZoneIdentifier: String
    var automaticallyManageLaunches: Bool

    init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        displayName: String,
        applicationPath: String,
        timeZoneIdentifier: String = "Asia/Shanghai",
        automaticallyManageLaunches: Bool = false
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.applicationPath = applicationPath
        self.timeZoneIdentifier = timeZoneIdentifier
        self.automaticallyManageLaunches = automaticallyManageLaunches
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case bundleIdentifier
        case displayName
        case applicationPath
        case timeZoneIdentifier
        case automaticallyManageLaunches
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        displayName = try container.decode(String.self, forKey: .displayName)
        applicationPath = try container.decode(String.self, forKey: .applicationPath)
        timeZoneIdentifier = try container.decode(String.self, forKey: .timeZoneIdentifier)
        automaticallyManageLaunches = try container.decodeIfPresent(Bool.self, forKey: .automaticallyManageLaunches) ?? false
    }

    var applicationURL: URL {
        if let installedURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return installedURL
        }
        return URL(fileURLWithPath: applicationPath)
    }
}
