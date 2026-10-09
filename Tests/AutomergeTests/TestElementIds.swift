@testable import Automerge
import XCTest

class ElementIdsTestCase: XCTestCase {
    func testElementIdsFindEachCharacter() throws {
        let doc = Document()
        doc.actor = ActorId(data: Data([0xAB, 0xCD]))!
        let text = try doc.putObject(obj: ObjId.ROOT, key: "text", ty: .Text)
        try doc.spliceText(obj: text, start: 0, delete: 0, value: "abc")

        let ids = try doc.elementIds(obj: text, range: 0 ..< 3)
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(Set(ids).count, 3)
        XCTAssertEqual(ids.map(\.actor), Array(repeating: doc.actor, count: 3))
        XCTAssertEqual(try ids.map { try doc.position(obj: text, elementId: $0) }, [0, 1, 2])
        XCTAssertEqual(ids[0].description, "\(ids[0].counter)@abcd")

        try doc.spliceText(obj: text, start: 0, delete: 0, value: "xy")
        XCTAssertEqual(try ids.map { try doc.position(obj: text, elementId: $0) }, [2, 3, 4])
        XCTAssertEqual(try doc.elementIds(obj: text, range: 2 ..< 5), ids)
    }

    func testRemovingAnInsertionLeavesTextTypedInsideIt() throws {
        // The fork's actor sorts first, so merging it moves the document's own actor to a later index.
        let doc = Document()
        doc.actor = ActorId(data: Data(repeating: 0xFF, count: 16))!
        let text = try doc.putObject(obj: ObjId.ROOT, key: "text", ty: .Text)
        try doc.spliceText(obj: text, start: 0, delete: 0, value: "Notes: ")
        try doc.spliceText(obj: text, start: 7, delete: 0, value: "hello")
        let inserted = try doc.elementIds(obj: text, range: 7 ..< 12)

        let fork = doc.fork()
        fork.actor = ActorId(data: Data(repeating: 0x00, count: 16))!
        try fork.spliceText(obj: text, start: 9, delete: 0, value: "XY")
        try doc.merge(other: fork)
        XCTAssertEqual(try doc.text(obj: text), "Notes: heXYllo")

        let positions = try inserted.compactMap { try doc.position(obj: text, elementId: $0) }
        XCTAssertEqual(positions, [7, 8, 11, 12, 13])
        for position in positions.reversed() {
            try doc.spliceText(obj: text, start: position, delete: 1)
        }
        XCTAssertEqual(try doc.text(obj: text), "Notes: XY")
    }

    func testElementIdsCountInTheTextEncoding() throws {
        let doc = Document(textEncoding: .utf16)
        let text = try doc.putObject(obj: ObjId.ROOT, key: "text", ty: .Text)
        try doc.spliceText(obj: text, start: 0, delete: 0, value: "a😀b")

        let ids = try doc.elementIds(obj: text, range: 0 ..< 4)
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(try ids.map { try doc.position(obj: text, elementId: $0) }, [0, 1, 3])
        // A range that starts or ends inside the surrogate pair includes the whole character.
        XCTAssertEqual(try doc.elementIds(obj: text, range: 2 ..< 3), [ids[1]])
        XCTAssertEqual(try doc.elementIds(obj: text, range: 0 ..< 2), [ids[0], ids[1]])
        XCTAssertEqual(try doc.elementIds(obj: text, range: 2 ..< 4), [ids[1], ids[2]])
    }

    func testEachUnicodeScalarIsOneElement() throws {
        // A combining accent and a flag are each one Character, but two Unicode scalars.
        let doc = Document(textEncoding: .utf16)
        let text = try doc.putObject(obj: ObjId.ROOT, key: "text", ty: .Text)
        try doc.spliceText(obj: text, start: 0, delete: 0, value: "e\u{301}🇫🇮")

        let ids = try doc.elementIds(obj: text, range: 0 ..< 6)
        XCTAssertEqual(ids.count, 4)
        XCTAssertEqual(try ids.map { try doc.position(obj: text, elementId: $0) }, [0, 1, 2, 4])
    }

    func testElementIdsIgnoreTheRangePastTheEnd() throws {
        let doc = Document()
        let text = try doc.putObject(obj: ObjId.ROOT, key: "text", ty: .Text)
        try doc.spliceText(obj: text, start: 0, delete: 0, value: "ab")

        XCTAssertEqual(try doc.elementIds(obj: text, range: 1 ..< 10).count, 1)
        XCTAssertEqual(try doc.elementIds(obj: text, range: 2 ..< 10), [])
        XCTAssertEqual(try doc.elementIds(obj: text, range: 5 ..< 10), [])
        XCTAssertEqual(try doc.elementIds(obj: text, range: 1 ..< 1), [])
    }

    func testPositionOfADeletedElementIsNil() throws {
        let doc = Document()
        let text = try doc.putObject(obj: ObjId.ROOT, key: "text", ty: .Text)
        try doc.spliceText(obj: text, start: 0, delete: 0, value: "abc")
        let ids = try doc.elementIds(obj: text, range: 0 ..< 3)

        try doc.spliceText(obj: text, start: 1, delete: 1)
        XCTAssertEqual(try ids.map { try doc.position(obj: text, elementId: $0) }, [0, nil, 1])

        try doc.spliceText(obj: text, start: 1, delete: 1)
        XCTAssertEqual(try ids.map { try doc.position(obj: text, elementId: $0) }, [0, nil, nil])
    }

    func testElementIdsInArrays() throws {
        let doc = Document()
        let list = try doc.putObject(obj: ObjId.ROOT, key: "list", ty: .List)
        try doc.splice(obj: list, start: 0, delete: 0, values: [.Int(1), .Int(2), .Int(3)])
        let ids = try doc.elementIds(obj: list, range: 0 ..< 3)
        XCTAssertEqual(ids.count, 3)

        try doc.insert(obj: list, index: 0, value: .Int(0))
        XCTAssertEqual(try ids.map { try doc.position(obj: list, elementId: $0) }, [1, 2, 3])

        // Setting a new value at an index gives that element a new identifier.
        try doc.put(obj: list, index: 2, value: .Int(20))
        XCTAssertNil(try doc.position(obj: list, elementId: ids[1]))
        let replaced = try XCTUnwrap(doc.elementIds(obj: list, range: 2 ..< 3).first)
        XCTAssertNotEqual(replaced, ids[1])
        XCTAssertEqual(try doc.position(obj: list, elementId: replaced), 2)
    }

    func testPositionInAnotherObjectIsNil() throws {
        let doc = Document()
        let first = try doc.putObject(obj: ObjId.ROOT, key: "first", ty: .Text)
        let second = try doc.putObject(obj: ObjId.ROOT, key: "second", ty: .Text)
        try doc.spliceText(obj: first, start: 0, delete: 0, value: "a")
        try doc.spliceText(obj: second, start: 0, delete: 0, value: "b")
        let id = try XCTUnwrap(doc.elementIds(obj: first, range: 0 ..< 1).first)

        XCTAssertEqual(try doc.position(obj: first, elementId: id), 0)
        XCTAssertNil(try doc.position(obj: second, elementId: id))
        XCTAssertNil(try doc.position(obj: second, elementId: id, heads: doc.heads()))
    }

    func testElementIdsTakeRangesBeyondThirtyTwoBits() throws {
        let doc = Document()
        let text = try doc.putObject(obj: ObjId.ROOT, key: "text", ty: .Text)
        try doc.spliceText(obj: text, start: 0, delete: 0, value: "ab")
        let beyond = UInt64(UInt32.max) + 1

        XCTAssertEqual(try doc.elementIds(obj: text, range: 0 ..< beyond).count, 2)
        XCTAssertEqual(try doc.elementIds(obj: text, range: beyond ..< beyond + 1), [])
        XCTAssertEqual(try doc.elementIds(obj: text, range: 0 ..< UInt64.max).count, 2)
    }

    func testElementIdsStayEqualAcrossMerges() throws {
        // The fork's actor sorts first, so merging it changes the index of the document's own actor, which the
        // object identifiers' bytes include.
        let doc = Document()
        doc.actor = ActorId(data: Data(repeating: 0xFF, count: 16))!
        let text = try doc.putObject(obj: ObjId.ROOT, key: "text", ty: .Text)
        try doc.spliceText(obj: text, start: 0, delete: 0, value: "ab")
        let before = try doc.elementIds(obj: text, range: 0 ..< 2)

        let fork = doc.fork()
        fork.actor = ActorId(data: Data(repeating: 0x00, count: 16))!
        try fork.spliceText(obj: text, start: 0, delete: 0, value: "x")
        try doc.merge(other: fork)

        let after = try doc.elementIds(obj: text, range: 1 ..< 3)
        XCTAssertEqual(after, before)
        XCTAssertEqual(Set(after), Set(before))
        XCTAssertEqual(try before.map { try doc.position(obj: text, elementId: $0) }, [1, 2])
    }

    func testElementIdsAtHeads() throws {
        let doc = Document()
        let text = try doc.putObject(obj: ObjId.ROOT, key: "text", ty: .Text)
        try doc.spliceText(obj: text, start: 0, delete: 0, value: "abc")
        let heads = doc.heads()
        let ids = try doc.elementIds(obj: text, range: 0 ..< 3)

        try doc.spliceText(obj: text, start: 0, delete: 2, value: "x")
        let added = try XCTUnwrap(doc.elementIds(obj: text, range: 0 ..< 1).first)

        XCTAssertEqual(try doc.elementIds(obj: text, range: 0 ..< 3, heads: heads), ids)
        XCTAssertEqual(try doc.position(obj: text, elementId: ids[1], heads: heads), 1)
        XCTAssertNil(try doc.position(obj: text, elementId: ids[1]))
        XCTAssertEqual(try doc.position(obj: text, elementId: ids[2]), 1)
        XCTAssertNil(try doc.position(obj: text, elementId: added, heads: heads))
    }

    func testElementIdsRefuseMaps() throws {
        let doc = Document()
        let map = try doc.putObject(obj: ObjId.ROOT, key: "map", ty: .Map)
        try doc.put(obj: map, key: "a", value: .String("b"))
        let text = try doc.putObject(obj: ObjId.ROOT, key: "text", ty: .Text)
        try doc.spliceText(obj: text, start: 0, delete: 0, value: "a")
        let id = try XCTUnwrap(doc.elementIds(obj: text, range: 0 ..< 1).first)

        XCTAssertThrowsError(try doc.elementIds(obj: map, range: 0 ..< 1)) { error in
            guard let docError = error as? DocError, case .WrongObjectType = docError.inner else {
                return XCTFail("Expected WrongObjectType, got \(error)")
            }
        }
        XCTAssertThrowsError(try doc.position(obj: map, elementId: id)) { error in
            guard let docError = error as? DocError, case .WrongObjectType = docError.inner else {
                return XCTFail("Expected WrongObjectType, got \(error)")
            }
        }
    }
}
