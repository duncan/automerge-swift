import Automerge
import Foundation
import XCTest

/// Asserts that `expression` throws a `DocError`.
private func assertThrowsDocError<T>(
    _ expression: @autoclosure () throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertThrowsError(try expression(), message(), file: file, line: line) { error in
        XCTAssertTrue(error is DocError, "expected DocError, got \(error)", file: file, line: line)
    }
}

/// Indices and counts too large for a 32-bit `usize`. On 32-bit targets such as WASM, these used to wrap
/// around to small numbers, so an insert at 2^32 inserted at index 0. They must behave like any other
/// index past the end.
class LargeIndexTests: XCTestCase {
    let indices: [UInt64] = [1 << 32, (1 << 32) + 1, UInt64(UInt32.max) + 3, .max]

    /// A document with a three-element list and the text "hello".
    struct Fixture {
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

        func listValues() throws -> [Value] {
            try doc.values(obj: list)
        }
    }

    func testWritingToAListAtAHugeIndexThrowsAndChangesNothing() throws {
        for index in indices {
            let f = try Fixture()
            let before = try f.listValues()
            assertThrowsDocError(try f.doc.insert(obj: f.list, index: index, value: .Int(1)), "index \(index)")
            assertThrowsDocError(try f.doc.insertObject(obj: f.list, index: index, ty: .Map), "index \(index)")
            assertThrowsDocError(try f.doc.put(obj: f.list, index: index, value: .Int(1)), "index \(index)")
            assertThrowsDocError(try f.doc.putObject(obj: f.list, index: index, ty: .Map), "index \(index)")
            assertThrowsDocError(try f.doc.delete(obj: f.list, index: index), "index \(index)")
            assertThrowsDocError(try f.doc.increment(obj: f.list, index: index, by: 1), "index \(index)")
            assertThrowsDocError(
                try f.doc.splice(obj: f.list, start: index, delete: 0, values: [.Int(1)]),
                "index \(index)"
            )
            XCTAssertEqual(try f.listValues(), before, "index \(index)")
        }
    }

    func testReadingAListAtAHugeIndexFindsNothing() throws {
        for index in indices {
            let f = try Fixture()
            let heads = f.doc.heads()
            XCTAssertNil(try f.doc.get(obj: f.list, index: index), "index \(index)")
            XCTAssertTrue(try f.doc.getAll(obj: f.list, index: index).isEmpty, "index \(index)")
            XCTAssertNil(try f.doc.getAt(obj: f.list, index: index, heads: heads), "index \(index)")
            XCTAssertTrue(try f.doc.getAllAt(obj: f.list, index: index, heads: heads).isEmpty, "index \(index)")
        }
    }

    func testEditingTextAtAHugeIndexThrowsAndChangesNothing() throws {
        for index in indices {
            let f = try Fixture()
            assertThrowsDocError(try f.doc.spliceText(obj: f.text, start: index, delete: 0, value: "x"), "index \(index)")
            assertThrowsDocError(
                try f.doc.mark(obj: f.text, start: 0, end: index, expand: .none, name: "bold", value: .Boolean(true)),
                "index \(index)"
            )
            XCTAssertEqual(try f.doc.text(obj: f.text), "hello", "index \(index)")
            XCTAssertTrue(try f.doc.marks(obj: f.text).isEmpty, "index \(index)")
        }
    }

    func testCursorAtAHugePositionIsAtTheEndOfTheText() throws {
        for index in indices {
            let f = try Fixture()
            let cursor = try f.doc.cursor(obj: f.text, position: index)
            XCTAssertEqual(try f.doc.position(obj: f.text, cursor: cursor), 5, "index \(index)")
            try f.doc.spliceText(obj: f.text, start: 5, delete: 0, value: "!")
            XCTAssertEqual(try f.doc.position(obj: f.text, cursor: cursor), 6, "index \(index)")
        }
    }

    func testDeletingAHugeCountDeletesToTheEnd() throws {
        let f = try Fixture()
        try f.doc.splice(obj: f.list, start: 1, delete: .max, values: [])
        XCTAssertEqual(try f.listValues(), [.Scalar(.String("a"))])
        try f.doc.spliceText(obj: f.text, start: 1, delete: .max)
        XCTAssertEqual(try f.doc.text(obj: f.text), "h")
    }

    func testDeletingAHugeNegativeCountPastTheStartThrows() throws {
        let f = try Fixture()
        assertThrowsDocError(try f.doc.splice(obj: f.list, start: 2, delete: .min, values: []))
        assertThrowsDocError(try f.doc.spliceText(obj: f.text, start: 3, delete: -.max))
        XCTAssertEqual(try f.listValues().count, 3)
        XCTAssertEqual(try f.doc.text(obj: f.text), "hello")
    }
}

class MarkBoundsTests: XCTestCase {
    /// automerge's `mark` applied the start of a mark whose end was past the end of the text before
    /// returning the error, leaving a mark over the rest of the text.
    func testMarkThatEndsPastTheEndOfTheTextThrowsAndAppliesNothing() throws {
        for end: UInt64 in [6, 10] {
            let doc = Document()
            let text = try doc.putObject(obj: .ROOT, key: "text", ty: .Text)
            try doc.spliceText(obj: text, start: 0, delete: 0, value: "hello")
            doc.commitWith(message: nil, timestamp: Date(timeIntervalSince1970: 0))
            let heads = doc.heads()

            assertThrowsDocError(
                try doc.mark(obj: text, start: 0, end: end, expand: .none, name: "bold", value: .Boolean(true)),
                "end \(end)"
            )
            doc.commitWith(message: nil, timestamp: Date(timeIntervalSince1970: 1))
            XCTAssertTrue(try doc.marks(obj: text).isEmpty, "end \(end)")
            XCTAssertEqual(doc.heads(), heads, "end \(end)")
        }
    }

    func testMarkThatEndsExactlyAtTheEndOfTheTextApplies() throws {
        let doc = Document()
        let text = try doc.putObject(obj: .ROOT, key: "text", ty: .Text)
        try doc.spliceText(obj: text, start: 0, delete: 0, value: "hello")
        try doc.mark(obj: text, start: 1, end: 5, expand: .none, name: "bold", value: .Boolean(true))
        XCTAssertEqual(try doc.marks(obj: text), [Mark(start: 1, end: 5, name: "bold", value: .Boolean(true))])
    }
}
