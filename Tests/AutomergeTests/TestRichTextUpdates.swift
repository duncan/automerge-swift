@testable import Automerge
import XCTest

private let bold: [String: ScalarValue] = ["bold": .Boolean(true)]

class RichTextUpdatesTestCase: XCTestCase {
    private func textDocument(_ contents: String = "") throws -> (Document, ObjId) {
        let doc = Document()
        let text = try doc.putObject(obj: ObjId.ROOT, key: "text", ty: .Text)
        try doc.spliceText(obj: text, start: 0, delete: 0, value: contents)
        return (doc, text)
    }

    private func assertThrowsDocError<T>(
        _ expression: @autoclosure () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertTrue(error is DocError, "Expected a DocError, got \(error)", file: file, line: line)
        }
    }

    // MARK: Unmark

    func testUnmarkRemovesAMarkFromPartOfItsRange() throws {
        let (doc, text) = try textDocument("abcdefghij")
        try doc.mark(obj: text, start: 0, end: 10, expand: .after, name: "bold", value: .Boolean(true))
        try doc.unmark(obj: text, start: 4, end: 10, expand: .none, name: "bold")

        XCTAssertEqual(try doc.spans(obj: text), [
            .text("abcd", marks: bold),
            .text("efghij", marks: [:]),
        ])
    }

    func testUnmarkInTheMiddleSplitsTheMark() throws {
        let (doc, text) = try textDocument("abcdefghij")
        try doc.mark(obj: text, start: 0, end: 10, expand: .after, name: "bold", value: .Boolean(true))
        try doc.unmark(obj: text, start: 3, end: 6, expand: .none, name: "bold")

        XCTAssertEqual(try doc.spans(obj: text), [
            .text("abc", marks: bold),
            .text("def", marks: [:]),
            .text("ghij", marks: bold),
        ])
    }

    func testUnmarkLeavesOtherMarksAlone() throws {
        let (doc, text) = try textDocument("abcdef")
        try doc.mark(obj: text, start: 0, end: 6, expand: .after, name: "bold", value: .Boolean(true))
        try doc.mark(obj: text, start: 0, end: 6, expand: .after, name: "italic", value: .Boolean(true))
        try doc.unmark(obj: text, start: 0, end: 6, expand: .none, name: "italic")

        XCTAssertEqual(try doc.spans(obj: text), [.text("abcdef", marks: bold)])
    }

    func testUnmarkingTextWithoutTheMarkChangesNothing() throws {
        let (doc, text) = try textDocument("abcdef")
        try doc.mark(obj: text, start: 0, end: 3, expand: .none, name: "bold", value: .Boolean(true))
        try doc.unmark(obj: text, start: 3, end: 6, expand: .none, name: "bold")
        try doc.unmark(obj: text, start: 0, end: 6, expand: .none, name: "italic")

        XCTAssertEqual(try doc.spans(obj: text), [
            .text("abc", marks: bold),
            .text("def", marks: [:]),
        ])
    }

    func testUnmarkMergesWithAPeersEdits() throws {
        let (doc, text) = try textDocument("abcdef")
        try doc.mark(obj: text, start: 0, end: 6, expand: .after, name: "bold", value: .Boolean(true))

        let peer = doc.fork()
        try peer.spliceText(obj: text, start: 0, delete: 0, value: "X")
        try doc.unmark(obj: text, start: 3, end: 6, expand: .none, name: "bold")
        try doc.merge(other: peer)

        XCTAssertEqual(try doc.text(obj: text), "Xabcdef")
        XCTAssertEqual(try doc.marks(obj: text).map(\.name), ["bold"])
        XCTAssertEqual(try doc.marks(obj: text).first?.end, 4)
    }

    func testUnmarkRejectsARangeOutOfBounds() throws {
        let (doc, text) = try textDocument("abc")
        try doc.mark(obj: text, start: 0, end: 3, expand: .none, name: "bold", value: .Boolean(true))
        assertThrowsDocError(try doc.unmark(obj: text, start: 0, end: 4, expand: .none, name: "bold"))
        assertThrowsDocError(try doc.unmark(obj: text, start: 4, end: 4, expand: .none, name: "bold"))
        assertThrowsDocError(try doc.unmark(obj: text, start: 0, end: .max, expand: .none, name: "bold"))
        XCTAssertEqual(try doc.spans(obj: text), [.text("abc", marks: bold)], "A rejected unmark changes nothing")
    }

    func testUnmarkRejectsObjectsOtherThanText() throws {
        let doc = Document()
        let list = try doc.putObject(obj: ObjId.ROOT, key: "list", ty: .List)
        assertThrowsDocError(try doc.unmark(obj: list, start: 0, end: 0, expand: .none, name: "bold"))
        assertThrowsDocError(try doc.unmark(obj: ObjId.ROOT, start: 0, end: 0, expand: .none, name: "bold"))
    }

    // MARK: Moving cursors

    func testCursorsMoveToTheChosenSideWhenTheirElementIsDeleted() throws {
        let (doc, text) = try textDocument("ABC")
        let after = try doc.cursor(obj: text, position: 1, move: .after)
        let before = try doc.cursor(obj: text, position: 1, move: .before)
        XCTAssertEqual(try doc.position(obj: text, cursor: after), 1)
        XCTAssertEqual(try doc.position(obj: text, cursor: before), 1)

        try doc.spliceText(obj: text, start: 1, delete: 1)
        XCTAssertEqual(try doc.text(obj: text), "AC")
        XCTAssertEqual(try doc.position(obj: text, cursor: after), 1, "An after cursor moves to C")
        XCTAssertEqual(try doc.position(obj: text, cursor: before), 0, "A before cursor moves to A")
    }

    func testTheDefaultCursorMovesAfter() throws {
        let (doc, text) = try textDocument("ABC")
        let cursor = try doc.cursor(obj: text, position: 1)
        try doc.spliceText(obj: text, start: 1, delete: 1)
        XCTAssertEqual(try doc.position(obj: text, cursor: cursor), 1)
    }

    func testCursorsFollowTheirElementWhileItExists() throws {
        let (doc, text) = try textDocument("ABC")
        let after = try doc.cursor(obj: text, position: 1, move: .after)
        let before = try doc.cursor(obj: text, position: 1, move: .before)

        try doc.spliceText(obj: text, start: 0, delete: 0, value: "ZZ")
        XCTAssertEqual(try doc.position(obj: text, cursor: after), 3)
        XCTAssertEqual(try doc.position(obj: text, cursor: before), 3)
    }

    func testCursorsWithNoNeighbourGoToTheEnds() throws {
        let (doc, text) = try textDocument("ABC")
        let after = try doc.cursor(obj: text, position: 1, move: .after)
        let before = try doc.cursor(obj: text, position: 1, move: .before)

        try doc.spliceText(obj: text, start: 0, delete: 3)
        try doc.spliceText(obj: text, start: 0, delete: 0, value: "new")
        XCTAssertEqual(try doc.position(obj: text, cursor: after), 3, "No later element is left, so it's at the end")
        XCTAssertEqual(try doc.position(obj: text, cursor: before), 0, "No earlier element is left, so it's at the start")
    }

    func testACursorAtTheEndStaysAtTheEnd() throws {
        let (doc, text) = try textDocument("ABC")
        let before = try doc.cursor(obj: text, position: 3, move: .before)
        let after = try doc.cursor(obj: text, position: 3, move: .after)

        try doc.spliceText(obj: text, start: 3, delete: 0, value: "DEF")
        XCTAssertEqual(try doc.position(obj: text, cursor: before), 6)
        XCTAssertEqual(try doc.position(obj: text, cursor: after), 6)
    }

    func testMovingCursorsAtHeads() throws {
        let (doc, text) = try textDocument("ABC")
        let heads = doc.heads()
        try doc.spliceText(obj: text, start: 0, delete: 0, value: "ZZ")

        let before = try doc.cursor(obj: text, position: 1, heads: heads, move: .before)
        let after = try doc.cursor(obj: text, position: 1, heads: heads, move: .after)
        XCTAssertEqual(try doc.position(obj: text, cursor: before), 3, "Position 1 at the earlier heads was B")

        try doc.spliceText(obj: text, start: 3, delete: 1)
        XCTAssertEqual(try doc.text(obj: text), "ZZAC")
        XCTAssertEqual(try doc.position(obj: text, cursor: before), 2)
        XCTAssertEqual(try doc.position(obj: text, cursor: after), 3)
    }

    func testMovingCursorsInLists() throws {
        let doc = Document()
        let list = try doc.putObject(obj: ObjId.ROOT, key: "list", ty: .List)
        for (index, value) in ["a", "b", "c"].enumerated() {
            try doc.insert(obj: list, index: UInt64(index), value: .String(value))
        }
        let before = try doc.cursor(obj: list, position: 1, move: .before)
        let after = try doc.cursor(obj: list, position: 1, move: .after)

        try doc.delete(obj: list, index: 1)
        XCTAssertEqual(try doc.position(obj: list, cursor: before), 0)
        XCTAssertEqual(try doc.position(obj: list, cursor: after), 1)
    }

    // MARK: Update spans

    func testUpdateSpansFillsAnEmptyTextObject() throws {
        let (doc, text) = try textDocument()
        let spans: [Span] = [
            .block(["type": .scalar(.String("paragraph"))]),
            .text("Hello, ", marks: [:]),
            .text("world", marks: bold),
        ]
        try doc.updateSpans(obj: text, spans: spans)

        XCTAssertEqual(try doc.spans(obj: text), spans)
        XCTAssertEqual(try doc.text(obj: text), "\u{FFFC}Hello, world")
    }

    func testUpdateSpansChangesOnlyWhatDiffers() throws {
        let (doc, text) = try textDocument("Hello world")
        let cursor = try doc.cursor(obj: text, position: 6)

        try doc.updateSpans(obj: text, spans: [.text("Hello brave world", marks: [:])])
        XCTAssertEqual(try doc.text(obj: text), "Hello brave world")
        XCTAssertEqual(try doc.position(obj: text, cursor: cursor), 12, "The w is the same character as before")
    }

    func testUpdateSpansMergesWithAPeersEdits() throws {
        let (doc, text) = try textDocument("Hello world")
        let peer = doc.fork()
        try peer.spliceText(obj: text, start: 11, delete: 0, value: "!")

        try doc.updateSpans(obj: text, spans: [.text("Hello brave world", marks: [:])])
        try doc.merge(other: peer)
        XCTAssertEqual(try doc.text(obj: text), "Hello brave world!")
    }

    func testUpdateSpansAddsAndRemovesMarks() throws {
        let (doc, text) = try textDocument("Hello world")
        try doc.updateSpans(obj: text, spans: [
            .text("Hello ", marks: [:]),
            .text("world", marks: bold),
        ])
        XCTAssertEqual(try doc.spans(obj: text), [.text("Hello ", marks: [:]), .text("world", marks: bold)])

        try doc.updateSpans(obj: text, spans: [.text("Hello world", marks: [:])])
        XCTAssertEqual(try doc.spans(obj: text), [.text("Hello world", marks: [:])])
    }

    func testUpdateSpansAddsAndRemovesBlocks() throws {
        let (doc, text) = try textDocument("onetwo")
        let paragraph: [String: AutomergeValue] = ["type": .scalar(.String("paragraph"))]
        let split: [Span] = [
            .block(paragraph),
            .text("one", marks: [:]),
            .block(paragraph),
            .text("two", marks: [:]),
        ]
        try doc.updateSpans(obj: text, spans: split)
        XCTAssertEqual(try doc.spans(obj: text), split)

        try doc.updateSpans(obj: text, spans: [.text("onetwo", marks: [:])])
        XCTAssertEqual(try doc.spans(obj: text), [.text("onetwo", marks: [:])])
    }

    func testUpdateSpansWithTheCurrentSpansChangesNothing() throws {
        let (doc, text) = try textDocument("Hello world")
        try doc.mark(obj: text, start: 0, end: 5, expand: .after, name: "bold", value: .Boolean(true))
        try doc.splitBlock(obj: text, index: 0, block: ["type": .scalar(.String("paragraph"))])
        let spans = try doc.spans(obj: text)
        let heads = doc.heads()

        try doc.updateSpans(obj: text, spans: spans)
        XCTAssertEqual(try doc.spans(obj: text), spans)
        XCTAssertEqual(doc.heads(), heads, "Nothing changed, so there's no new change")
    }

    func testUpdateSpansMarksExpandAsConfigured() throws {
        for (expand, expected) in [(ExpandMark.after, true), (ExpandMark.none, false)] {
            let (doc, text) = try textDocument("abc")
            try doc.updateSpans(obj: text, spans: [.text("abc", marks: bold)], defaultExpand: expand)
            try doc.spliceText(obj: text, start: 3, delete: 0, value: "X")
            let marked = try doc.spans(obj: text) == [.text("abcX", marks: bold)]
            XCTAssertEqual(marked, expected, "defaultExpand \(expand)")
        }
    }

    func testUpdateSpansExpandsNamedMarksAsConfigured() throws {
        let (doc, text) = try textDocument("abc")
        let marks: [String: ScalarValue] = ["bold": .Boolean(true), "link": .String("https://example.com")]
        try doc.updateSpans(
            obj: text,
            spans: [.text("abc", marks: marks)],
            defaultExpand: .after,
            expandByMark: ["link": .none]
        )
        try doc.spliceText(obj: text, start: 3, delete: 0, value: "X")

        XCTAssertEqual(try doc.spans(obj: text), [
            .text("abc", marks: marks),
            .text("X", marks: bold),
        ])
    }

    func testUpdateSpansRejectsObjectsOtherThanText() throws {
        let doc = Document()
        let list = try doc.putObject(obj: ObjId.ROOT, key: "list", ty: .List)
        assertThrowsDocError(try doc.updateSpans(obj: list, spans: [.text("abc", marks: [:])]))
        assertThrowsDocError(try doc.updateSpans(obj: ObjId.ROOT, spans: []))
    }
}
