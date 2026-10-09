import Foundation
import Darwin

struct MoonshineLine: Sendable {
    let id: UInt64
    let start: Double
    let end: Double
    let text: String
    let complete: Bool
}

enum FocusTargetPolicy {
    static func isParentProcess(_ processID: pid_t, parentProcessID: pid_t) -> Bool {
        processID == parentProcessID
    }
}
