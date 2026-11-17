import Foundation

/// The identifier of whoever made changes to an Automerge document.
///
/// An author is a person, an app, or anything else your app wants to attribute changes to. Give a document
/// its author when you create or load it, and every peer that receives its changes can read who made them:
///
/// ```swift
/// let doc = Document(author: AuthorId(uuid: currentUser.id))
/// try doc.put(obj: ObjId.ROOT, key: "title", value: .String("Hello"))
///
/// for hash in doc.getHistory() {
///     if let change = doc.change(hash: hash), let author = doc.author(of: change) {
///         print("\(author) made a change at \(change.timestamp)")
///     }
/// }
/// ```
///
/// An author is different from an actor. An ``ActorId`` identifies one copy of a document, so a person who
/// edits on a phone and a laptop has one author ID and two actors. For how the two interact, see
/// <doc:ChangesAndHistory#Authors-and-actors>.
///
/// > Important: Author IDs are permanent. They're stored in the document's history, sent to every peer, and
/// can't be removed. Don't put personal information, such as a name or an email address, in one. Use an
/// opaque identifier, such as a UUID, that your app maps to the person or app it stands for.
public struct AuthorId: Equatable, Hashable, Sendable {
    /// The largest number of bytes an author ID you create can have.
    public static let maximumByteCount = 128

    /// The bytes of the author ID.
    ///
    /// An author ID you create has between 1 and ``maximumByteCount`` bytes. Automerge itself sets no
    /// limits, so an author ID read from another peer's changes can be empty or longer.
    public let data: Data

    /// Creates an author ID from the contents of a UUID you provide.
    /// - Parameter uuid: The UUID that identifies the author.
    public init(uuid: UUID) {
        data = withUnsafeBytes(of: uuid.uuid) { Data($0) }
    }

    /// Creates an author ID from the bytes you provide.
    /// - Parameter data: Between 1 and ``maximumByteCount`` bytes that identify the author.
    /// - Returns: An author ID, or `nil` if the data is empty or too long.
    public init?(data: Data) {
        guard !data.isEmpty, data.count <= Self.maximumByteCount else {
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
