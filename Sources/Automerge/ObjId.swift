import AutomergeUniffi

/// The unique internal identifier for an object stored in an Automerge document.
public struct ObjId: Equatable, Hashable, Sendable {
    var bytes: [UInt8]
    /// The root identifier for an Automerge document.
    public static let ROOT = ObjId(bytes: AutomergeUniffi.root())

    // The bytes include a hint that can differ between two IDs for the same object, so automerge
    // compares and hashes them.
    public static func == (lhs: ObjId, rhs: ObjId) -> Bool {
        AutomergeUniffi.objIdEqual(a: lhs.bytes, b: rhs.bytes)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(AutomergeUniffi.objIdHash(id: bytes))
    }
}

extension ObjId: CustomDebugStringConvertible {
    public var debugDescription: String {
        if bytes == AutomergeUniffi.root() {
            return "ObjId.ROOT"
        } else {
            return "ObjId(\(bytes.map { Swift.String(format: "%02hhx", $0) }.joined()))"
        }
    }
}
