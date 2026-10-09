import struct AutomergeUniffi.ElementId

typealias FfiElementId = AutomergeUniffi.ElementId

/// The identifier of an element in an array or text object.
///
/// An element's identifier is the operation that created its value: the actor that made it and that actor's
/// operation counter. It stays the same wherever the element moves as others insert and delete around it, so you can
/// use it to find the element again, even after merging changes from other collaborators.
///
/// In a text object, each Unicode scalar and each block marker is an element, and keeps its identifier for as long as
/// it exists. A Swift `Character` can hold several scalars, such as a letter and its combining accent, or the two
/// halves of a flag, so it can be several elements. In an array, setting a new value at an index gives that element a
/// new identifier.
///
/// Read the identifiers of elements with ``Document/elementIds(obj:range:)``, and find an element's current position
/// with ``Document/position(obj:elementId:)``.
public struct ElementId: Sendable {
    /// The actor that created the element.
    public let actor: ActorId
    /// The actor's counter for the operation that created the element.
    public let counter: UInt64
    /// The object that holds the element, so that looking it up in another object finds nothing.
    let obj: ObjId

    init(ffi: FfiElementId) {
        actor = ActorId(ffi: ffi.actor)
        counter = ffi.counter
        obj = ObjId(bytes: ffi.obj)
    }

    func toFfi() -> FfiElementId {
        FfiElementId(obj: obj.bytes, actor: [UInt8](actor.data), counter: counter)
    }
}

// An operation's actor and counter identify it within a document, so they alone decide equality. The object's bytes
// include its actor's index in the document, which can change as actors arrive.
extension ElementId: Hashable {
    public static func == (lhs: ElementId, rhs: ElementId) -> Bool {
        lhs.actor == rhs.actor && lhs.counter == rhs.counter
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(actor)
        hasher.combine(counter)
    }
}

extension ElementId: CustomStringConvertible {
    /// The identifier in Automerge's form, `counter@actor`, with the actor in lowercase hex.
    public var description: String {
        "\(counter)@\(actor.data.map { String(format: "%02hhx", $0) }.joined())"
    }
}
