import Foundation

enum ActivityKind: Int32 {
    case read = 1
    case write = 2
}

struct NodeActivityPulse {
    let kind: ActivityKind
    let startedAt: CFTimeInterval
    let processName: String
    let url: URL
}
