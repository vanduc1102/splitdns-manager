import SplitDNSCore
import SwiftUI

extension ResolverStatus {
    var symbolName: String {
        switch self {
        case .active(let isReachable):
            isReachable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        case .mismatch:
            "exclamationmark.triangle.fill"
        case .notLoaded:
            "circle.dashed"
        case .unknown:
            "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .active(let isReachable):
            isReachable ? .green : .orange
        case .mismatch:
            .orange
        case .notLoaded, .unknown:
            .secondary
        }
    }

    var title: String {
        switch self {
        case .active(let isReachable):
            isReachable ? "Active" : "Active, but the name server is unreachable"
        case .mismatch:
            "Loaded with different name servers"
        case .notLoaded:
            "Not loaded by macOS"
        case .unknown:
            "Status unavailable"
        }
    }

    var explanation: String? {
        switch self {
        case .active(let isReachable):
            isReachable ? nil : "macOS uses this resolver, but cannot reach its name servers right now (VPN off?)."
        case .mismatch(let loaded):
            "macOS currently uses \(loaded.joined(separator: ", ")) for this domain, not the servers in this file."
        case .notLoaded:
            "macOS has no resolver for this domain. It may need a moment, or the file has no valid name server."
        case .unknown:
            nil
        }
    }
}
