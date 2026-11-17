import enum AutomergeUniffi.MoveCursor
import enum AutomergeUniffi.Position

typealias FfiPosition = AutomergeUniffi.Position
typealias FfiMoveCursor = AutomergeUniffi.MoveCursor

/// A opaque type that represents a stable location of the character following the location reference at creation within an array or text object that adjusts with insertions and deletions to
/// maintain its relative position.
///
/// Create a cursor using ``Document/cursor(obj:position:)``, or ``Document/cursor(obj:position:heads:)`` to place a
/// cursor at the point in time indicated by the `heads` parameter.
/// Retrieve the position of the cursor reference from the document using ``Document/position(obj:cursor:)``, or use
/// ``Document/position(obj:cursor:heads:)`` to get the position at a previous point in time.
public struct Cursor: Equatable, Hashable, Sendable {
    var bytes: [UInt8]
}

extension Cursor: CustomStringConvertible {
    /// The bytes that describe the cursor.
    public var description: String {
        bytes.map { Swift.String(format: "%02hhx", $0) }.joined().uppercased()
    }
}

/// A type that indicates where a cursor goes when the element it refers to is deleted.
///
/// A cursor refers to one element of a list or text object, such as a character. While that element exists,
/// the cursor's position is the element's position. When it's deleted, the cursor moves to a neighboring
/// element that existed when you created the cursor:
///
/// ```swift
/// "ABC"   // a cursor at 1 refers to B
/// "AC"    // after deleting B, an .after cursor refers to C, at position 1,
///         // and a .before cursor refers to A, at position 0
/// ```
///
/// Choose ``after`` for the start of a selection or range and ``before`` for its end, so the range shrinks
/// rather than grows when the text at its edges is deleted. A cursor at the end of the object stays at the
/// end, whichever you choose.
public enum MoveCursor: Equatable, Hashable, Sendable {
    /// The cursor moves to the nearest earlier element, or to the start of the object if there is none.
    case before
    /// The cursor moves to the nearest later element, or to the end of the object if there is none.
    case after

    func toFfi() -> FfiMoveCursor {
        switch self {
        case .before:
            return .before
        case .after:
            return .after
        }
    }
}

/// An umbrella type that represents a location within an array or text object.
///
/// ### See Also
/// - ``Document/cursor(obj:position:)``
/// - ``Document/cursor(obj:position:heads:)``
public enum Position {
    /// A stable location character or array position that follows that location regardless of Document changes.
    case cursor(Cursor)
    /// An absolute index position within an array or text object.
    case index(UInt64)
}

extension Position {
    func toFfi() -> FfiPosition {
        switch self {
        case let .cursor(cursor):
            return .cursor(position: cursor.bytes)
        case let .index(index):
            return .index(position: index)
        }
    }
}
