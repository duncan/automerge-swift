import struct AutomergeUniffi.Change
import Foundation

typealias FfiChange = AutomergeUniffi.Change

/// A type that encapsulates a change, and any associated metadata, to an Automerge document.
public struct Change: Equatable {
    /// The identity of the actor that made the change.
    public let actorId: ActorId
    /// The author recorded with the change, if any.
    ///
    /// Automerge records an author only with an actor's first change. To find the author of any of an
    /// actor's changes, use ``Document/author(for:)`` with ``actorId``.
    public let author: AuthorId?
    /// An optional message associated with the change.
    public let message: String?
    /// The list of changes that this change depends upon.
    public let deps: [ChangeHash]
    /// The timestamp of the change.
    public let timestamp: Date
    /// The encoded bytes of the change operation.
    public let bytes: Data
    /// The identity of the change, its hash.
    public let hash: ChangeHash

    init(_ ffi: FfiChange) {
        actorId = ActorId(ffi: ffi.actorId)
        author = ffi.author.map(AuthorId.init(ffi:))
        message = ffi.message
        deps = ffi.deps.map(ChangeHash.init(bytes:))
        timestamp = Date(timeIntervalSince1970: TimeInterval(ffi.timestamp))
        bytes = Data(ffi.bytes)
        hash = ChangeHash(bytes: ffi.hash)
    }
}
