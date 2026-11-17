import Foundation

/// The identifier of the author of changes to an Automerge document.
///
/// An actor identifies one copy of a document making changes, while an author identifies who
/// made them: a person, an app, or anything else your app wants to attribute changes to. One
/// author can have many actors, for example one for each device or each copy of a document, but
/// each actor has at most one author.
///
/// An author ID is opaque bytes that your app chooses. Automerge records it with an actor's first
/// change, and every peer that receives that change can read it with ``Document/author(for:)``
/// or ``Change/author``.
///
/// To write changes as an author, set ``Document/author`` before the document's first change
/// with its current actor. See ``Document/author`` for how it interacts with ``Document/actor``.
public struct AuthorId: Equatable, Hashable, Sendable {
    /// The bytes of the author ID.
    public let data: Data

    /// Creates an author ID from the bytes you provide.
    /// - Parameter data: The bytes that identify the author. They can't be empty.
    public init?(data: Data) {
        guard !data.isEmpty else {
            return nil
        }
        self.data = data
    }

    init(ffi: [UInt8]) {
        data = Data(ffi)
    }
}

extension AuthorId: CustomStringConvertible {
    /// A hex-encoded string that represents the bytes of the author ID.
    public var description: String {
        data.map { String(format: "%02hhX", $0) }.joined()
    }
}
