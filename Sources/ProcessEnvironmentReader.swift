import Darwin
import Foundation

enum ManagedAppLaunchStatus: Equatable {
    case notRunning
    case applied(String)
    case notApplied
    case mismatched(actual: String)
    case unavailable

    var label: String {
        switch self {
        case .notRunning:
            return "未运行"
        case .applied:
            return "已应用指定时区"
        case .notApplied:
            return "运行中，但未应用"
        case let .mismatched(actual):
            return "时区不一致：\(actual)"
        case .unavailable:
            return "运行中，无法确认"
        }
    }

    var menuLabel: String {
        switch self {
        case .notRunning: return "未运行"
        case .applied: return "已应用"
        case .notApplied: return "未应用"
        case .mismatched: return "时区不一致"
        case .unavailable: return "无法确认"
        }
    }

    var symbolName: String {
        switch self {
        case .notRunning: return "circle"
        case .applied: return "checkmark.circle.fill"
        case .notApplied: return "exclamationmark.circle.fill"
        case .mismatched: return "exclamationmark.triangle.fill"
        case .unavailable: return "questionmark.circle.fill"
        }
    }
}

enum ProcessEnvironmentReader {
    static func environment(for processIdentifier: pid_t) -> [String: String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, processIdentifier]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: size)
        let result = bytes.withUnsafeMutableBytes { rawBuffer in
            sysctl(&mib, UInt32(mib.count), rawBuffer.baseAddress, &size, nil, 0)
        }
        guard result == 0, size >= MemoryLayout<Int32>.size else { return nil }

        let argumentCount: Int32 = bytes.withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(as: Int32.self)
        }
        var cursor = MemoryLayout<Int32>.size

        skipString(in: bytes, cursor: &cursor, limit: size)
        skipNulls(in: bytes, cursor: &cursor, limit: size)

        for _ in 0..<max(argumentCount, 0) {
            skipString(in: bytes, cursor: &cursor, limit: size)
        }

        var environment: [String: String] = [:]
        while cursor < size {
            skipNulls(in: bytes, cursor: &cursor, limit: size)
            guard cursor < size else { break }
            let start = cursor
            skipString(in: bytes, cursor: &cursor, limit: size)
            guard cursor > start,
                  let value = String(bytes: bytes[start..<(cursor - 1)], encoding: .utf8),
                  let separator = value.firstIndex(of: "=") else { continue }
            environment[String(value[..<separator])] = String(value[value.index(after: separator)...])
        }
        return environment
    }

    private static func skipString(in bytes: [UInt8], cursor: inout Int, limit: Int) {
        while cursor < limit, bytes[cursor] != 0 {
            cursor += 1
        }
        if cursor < limit { cursor += 1 }
    }

    private static func skipNulls(in bytes: [UInt8], cursor: inout Int, limit: Int) {
        while cursor < limit, bytes[cursor] == 0 {
            cursor += 1
        }
    }
}
