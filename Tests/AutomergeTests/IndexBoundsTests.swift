import Automerge
import Foundation
import Testing

/// Indices and counts too large for a 32-bit `usize`. On 32-bit targets such as WASM, these used to wrap
/// around to small numbers, so an insert at 2^32 inserted at index 0. They must behave like any other
/// index past the end.
@Suite("Indices beyond 32 bits")
struct LargeIndexTests {
    static let indices: [UInt64] = [1 << 32, (1 << 32) + 1, UInt64(UInt32.max) + 3, .max]

    let doc = Document()
    let list: ObjId
    let text: ObjId

    init() throws {
        list = try doc.putObject(obj: .ROOT, key: "list", ty: .List)
        for (index, value) in ["a", "b", "c"].enumerated() {
            try doc.insert(obj: list, index: UInt64(index), value: .String(value))
        }
        text = try doc.putObject(obj: .ROOT, key: "text", ty: .Text)
        try doc.spliceText(obj: text, start: 0, delete: 0, value: "hello")
    }

    private var listValues: [Value] {
        get throws { try doc.values(obj: list) }
    }

    @Test("Writing to a list at a huge index throws and changes nothing", arguments: indices)
    func listWritesThrow(index: UInt64) throws {
        let before = try listValues
        #expect(throws: DocError.self) { try doc.insert(obj: list, index: index, value: .Int(1)) }
        #expect(throws: DocError.self) { try doc.insertObject(obj: list, index: index, ty: .Map) }
        #expect(throws: DocError.self) { try doc.put(obj: list, index: index, value: .Int(1)) }
        #expect(throws: DocError.self) { try doc.putObject(obj: list, index: index, ty: .Map) }
        #expect(throws: DocError.self) { try doc.delete(obj: list, index: index) }
        #expect(throws: DocError.self) { try doc.increment(obj: list, index: index, by: 1) }
        #expect(throws: DocError.self) { try doc.splice(obj: list, start: index, delete: 0, values: [.Int(1)]) }
        #expect(try listValues == before)
    }

    @Test("Reading a list at a huge index finds nothing", arguments: indices)
    func listReadsFindNothing(index: UInt64) throws {
        let heads = doc.heads()
        #expect(try doc.get(obj: list, index: index) == nil)
        #expect(try doc.getAll(obj: list, index: index).isEmpty)
        #expect(try doc.getAt(obj: list, index: index, heads: heads) == nil)
        #expect(try doc.getAllAt(obj: list, index: index, heads: heads).isEmpty)
    }

    @Test("Editing text at a huge index throws and changes nothing", arguments: indices)
    func textWritesThrow(index: UInt64) throws {
        #expect(throws: DocError.self) { try doc.spliceText(obj: text, start: index, delete: 0, value: "x") }
        #expect(throws: DocError.self) {
            try doc.mark(obj: text, start: 0, end: index, expand: .none, name: "bold", value: .Boolean(true))
        }
        let marks = try doc.marks(obj: text)
        #expect(try doc.text(obj: text) == "hello")
        #expect(marks.isEmpty)
    }

    @Test("A cursor at a huge position is at the end of the text", arguments: indices)
    func cursorAtHugePosition(index: UInt64) throws {
        let cursor = try doc.cursor(obj: text, position: index)
        #expect(try doc.position(obj: text, cursor: cursor) == 5)
        try doc.spliceText(obj: text, start: 5, delete: 0, value: "!")
        #expect(try doc.position(obj: text, cursor: cursor) == 6)
    }

    @Test("Deleting a huge count deletes to the end")
    func hugeDeleteCountClamps() throws {
        try doc.splice(obj: list, start: 1, delete: .max, values: [])
        #expect(try listValues == [.Scalar(.String("a"))])
        try doc.spliceText(obj: text, start: 1, delete: .max)
        #expect(try doc.text(obj: text) == "h")
    }

    @Test("Deleting a huge negative count past the start throws")
    func hugeNegativeDeleteCountThrows() throws {
        #expect(throws: DocError.self) { try doc.splice(obj: list, start: 2, delete: .min, values: []) }
        #expect(throws: DocError.self) { try doc.spliceText(obj: text, start: 3, delete: -.max) }
        #expect(try listValues.count == 3)
        #expect(try doc.text(obj: text) == "hello")
    }
}

@Suite("Marks out of bounds")
struct MarkBoundsTests {
    /// automerge's `mark` applied the start of a mark whose end was past the end of the text before
    /// returning the error, leaving a mark over the rest of the text.
    @Test("A mark that ends past the end of the text throws and applies nothing", arguments: [UInt64(6), 10])
    func markPastEndAppliesNothing(end: UInt64) throws {
        let doc = Document()
        let text = try doc.putObject(obj: .ROOT, key: "text", ty: .Text)
        try doc.spliceText(obj: text, start: 0, delete: 0, value: "hello")
        doc.commitWith(message: nil, timestamp: Date(timeIntervalSince1970: 0))
        let heads = doc.heads()

        #expect(throws: DocError.self) {
            try doc.mark(obj: text, start: 0, end: end, expand: .none, name: "bold", value: .Boolean(true))
        }
        doc.commitWith(message: nil, timestamp: Date(timeIntervalSince1970: 1))
        let marks = try doc.marks(obj: text)
        #expect(marks.isEmpty)
        #expect(doc.heads() == heads)
    }

    @Test("A mark that ends exactly at the end of the text applies")
    func markToEndApplies() throws {
        let doc = Document()
        let text = try doc.putObject(obj: .ROOT, key: "text", ty: .Text)
        try doc.spliceText(obj: text, start: 0, delete: 0, value: "hello")
        try doc.mark(obj: text, start: 1, end: 5, expand: .none, name: "bold", value: .Boolean(true))
        let marks = try doc.marks(obj: text)
        #expect(marks == [Mark(start: 1, end: 5, name: "bold", value: .Boolean(true))])
    }
}
