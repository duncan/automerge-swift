import AutomergeUniffi
import Foundation

typealias FfiChange = AutomergeUniffi.Change

/// A type that encapsulates a change, and any associated metadata, to an Automerge document.
public struct Change: Equatable {
    /// The identity of the actor that made the change.
    public let actorId: ActorId
    /// The author stored in this change itself, which is `nil` for most changes.
    ///
    /// Automerge stores an author only in the first change each actor makes, and it covers all that actor's
    /// changes. To find the author of any change, use ``Document/author(of:)``.
    public let recordedAuthor: AuthorId?
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

    /// Creates a change by decoding the bytes of an encoded change.
    ///
    /// Use this to inspect a change you've received before applying it, for example to check who made it.
    /// The bytes are those of a single change, as ``bytes`` provides.
    ///
    /// - Parameter bytes: The encoded bytes of one change.
    /// - Throws: ``DecodeChangeError`` if the bytes aren't a valid change.
    public init(bytes: Data) throws {
        self.init(try wrappedErrors(unexpected: .decodeChange) {
            try AutomergeUniffi.decodeChange(bytes: Array(bytes))
        })
    }

    init(_ ffi: FfiChange) {
        actorId = ActorId(ffi: ffi.actorId)
        recordedAuthor = ffi.author.map(AuthorId.init(ffi:))
        message = ffi.message
        deps = ffi.deps.map(ChangeHash.init(bytes:))
        timestamp = Date(timeIntervalSince1970: TimeInterval(ffi.timestamp))
        bytes = Data(ffi.bytes)
        hash = ChangeHash(bytes: ffi.hash)
    }
}
