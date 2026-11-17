import struct AutomergeUniffi.ChangeMetadata
import Foundation

typealias FfiChangeMetadata = AutomergeUniffi.ChangeMetadata

/// What a document records about a change: who made it, when, and what it follows.
///
/// Change metadata is a ``Change`` without its encoded operations, which makes it cheaper to read when you
/// only need to describe a document's history, for example to list who changed it and when:
///
/// ```swift
/// for change in doc.changeMetadata() {
///     print("\(change.timestamp): \(change.message ?? "no message")")
/// }
/// ```
///
/// To get the encoded change itself, for example to send it to another peer, use ``Document/change(hash:)``
/// with ``hash``.
public struct ChangeMetadata: Equatable, Hashable, Sendable {
    /// The identity of the change, its hash.
    public let hash: ChangeHash
    /// The identity of the actor that made the change.
    public let actorId: ActorId
    /// The author of the change, if it has one.
    ///
    /// Unlike ``Change/recordedAuthor``, this is set on every change an author's actor made, not only the
    /// first.
    public let author: AuthorId?
    /// The position of the change among those its actor made, starting at 1.
    public let sequenceNumber: UInt64
    /// The counter of the first operation in the change.
    ///
    /// Automerge numbers the operations in a document. A change holds the operations from `startOp` through
    /// ``maxOp``.
    public let startOp: UInt64
    /// The counter of the last operation in the change.
    public let maxOp: UInt64
    /// An optional message associated with the change.
    public let message: String?
    /// The timestamp of the change.
    public let timestamp: Date
    /// The changes that this change depends upon.
    public let deps: [ChangeHash]

    init(_ ffi: FfiChangeMetadata) {
        hash = ChangeHash(bytes: ffi.hash)
        actorId = ActorId(ffi: ffi.actorId)
        author = ffi.author.map(AuthorId.init(ffi:))
        sequenceNumber = ffi.seq
        startOp = ffi.startOp
        maxOp = ffi.maxOp
        message = ffi.message
        timestamp = Date(timeIntervalSince1970: TimeInterval(ffi.timestamp))
        deps = ffi.deps.map(ChangeHash.init(bytes:))
    }
}
