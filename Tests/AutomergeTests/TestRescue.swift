import Automerge
import Foundation
import XCTest

class RescueTestCase: XCTestCase {
    /// automerge's `broken_zero_width_mark.automerge` fixture: a document with a zero-width mark whose end
    /// comes before its beginning, which older versions of automerge wrote and 0.12.0 refuses to load.
    static let brokenMark = Data([
        0x85, 0x6f, 0x4a, 0x83, 0x86, 0x23, 0x30, 0x9a, 0x00, 0xc4, 0x01, 0x02,
        0x01, 0x00, 0x01, 0x01, 0x01, 0xde, 0x96, 0x1f, 0x4f, 0x79, 0x2d, 0x90,
        0x7f, 0x0b, 0xd9, 0xf5, 0x71, 0x4f, 0xe1, 0x33, 0x1f, 0x08, 0x2f, 0x59,
        0xd3, 0x99, 0x2a, 0x4d, 0x69, 0x32, 0x2a, 0x2b, 0x64, 0xd5, 0x61, 0xf5,
        0xe7, 0x07, 0x01, 0x04, 0x03, 0x05, 0x13, 0x05, 0x23, 0x02, 0x40, 0x04,
        0x43, 0x04, 0x56, 0x02, 0x0e, 0x01, 0x06, 0x02, 0x06, 0x11, 0x04, 0x13,
        0x08, 0x15, 0x0b, 0x21, 0x06, 0x23, 0x08, 0x34, 0x02, 0x42, 0x06, 0x56,
        0x06, 0x57, 0x04, 0x80, 0x01, 0x02, 0x94, 0x01, 0x03, 0xa5, 0x01, 0x0c,
        0x02, 0x00, 0x02, 0x01, 0x02, 0x01, 0x7e, 0x7f, 0x01, 0x7c, 0x01, 0x02,
        0x01, 0x04, 0x04, 0x00, 0x7f, 0x00, 0x03, 0x01, 0x7f, 0x00, 0x02, 0x01,
        0x04, 0x07, 0x00, 0x02, 0x02, 0x00, 0x04, 0x01, 0x00, 0x02, 0x02, 0x01,
        0x04, 0x04, 0x00, 0x05, 0x03, 0x01, 0x00, 0x02, 0x03, 0x00, 0x7f, 0x05,
        0x02, 0x01, 0x7e, 0x02, 0x6f, 0x31, 0x04, 0x74, 0x65, 0x78, 0x74, 0x00,
        0x06, 0x7f, 0x01, 0x03, 0x00, 0x04, 0x01, 0x7b, 0x04, 0x7d, 0x02, 0x7f,
        0x03, 0x03, 0x01, 0x02, 0x06, 0x02, 0x04, 0x02, 0x07, 0x04, 0x01, 0x03,
        0x00, 0x7f, 0x02, 0x04, 0x16, 0x74, 0x73, 0x78, 0x73, 0x08, 0x00, 0x02,
        0x01, 0x05, 0x00, 0x03, 0x7f, 0x06, 0x69, 0x74, 0x61, 0x6c, 0x69, 0x63,
        0x00, 0x04, 0x03
    ])

    func testADocumentWithABrokenMarkFailsToLoadButCanBeRescued() throws {
        XCTAssertThrowsError(try Document(Self.brokenMark)) { XCTAssert($0 is LoadError, "\($0)") }

        // The contents the Rust `rescue` test expects for this fixture.
        let doc = try Document(rescuing: Self.brokenMark)
        XCTAssertEqual(doc.keys(obj: .ROOT), ["o1", "text"])
        guard case let .Object(o1, .Text) = try doc.get(obj: .ROOT, key: "o1"),
              case let .Object(text, .Text) = try doc.get(obj: .ROOT, key: "text")
        else {
            return XCTFail("Expected text objects at `o1` and `text`")
        }
        XCTAssertEqual(try doc.text(obj: o1), "tsxs")
        XCTAssertEqual(try doc.text(obj: text), "")
    }

    func testARescuedDocumentHasOneChangeAndANewActor() throws {
        let doc = try Document(rescuing: Self.brokenMark)
        let history = doc.getHistory()
        XCTAssertEqual(history.count, 1)
        let change = try XCTUnwrap(history.first.flatMap { doc.change(hash: $0) })
        XCTAssertEqual(change.message, "Rescued from a document that failed to load")
        XCTAssertEqual(change.deps, [])
        XCTAssertEqual(change.actorId, doc.actor)
    }

    func testARescuedDocumentSavesReloadsAndSyncsLikeAnyOther() throws {
        let doc = try Document(rescuing: Self.brokenMark)
        try doc.put(obj: .ROOT, key: "added", value: .Boolean(true))

        let reloaded = try Document(doc.save())
        XCTAssertEqual(reloaded.keys(obj: .ROOT), ["added", "o1", "text"])
        XCTAssertEqual(try reloaded.get(obj: .ROOT, key: "added"), .Scalar(.Boolean(true)))
        XCTAssertEqual(reloaded.heads(), doc.heads())

        let peer = Document()
        let (docState, peerState) = (SyncState(), SyncState())
        for _ in 0 ..< 10 {
            var quiet = true
            if let message = doc.generateSyncMessage(state: docState) {
                quiet = false
                try peer.receiveSyncMessage(state: peerState, message: message)
            }
            if let message = peer.generateSyncMessage(state: peerState) {
                quiet = false
                try doc.receiveSyncMessage(state: docState, message: message)
            }
            if quiet { break }
        }
        XCTAssertEqual(peer.heads(), doc.heads())
        XCTAssertEqual(peer.keys(obj: .ROOT), ["added", "o1", "text"])
        guard case let .Object(o1, .Text) = try peer.get(obj: .ROOT, key: "o1") else {
            return XCTFail("Expected a text object at `o1`")
        }
        XCTAssertEqual(try peer.text(obj: o1), "tsxs")
    }

    func testRescuingAValidDocumentKeepsItsVisibleContentsWithoutMarks() throws {
        let original = Document()
        let text = try original.putObject(obj: .ROOT, key: "text", ty: .Text)
        try original.spliceText(obj: text, start: 0, delete: 0, value: "Hello marks")
        try original.mark(obj: text, start: 0, end: 5, expand: .none, name: "bold", value: .Boolean(true))
        let list = try original.putObject(obj: .ROOT, key: "list", ty: .List)
        try original.insert(obj: list, index: 0, value: .Int(1))
        try original.insert(obj: list, index: 1, value: .String("two"))
        let map = try original.putObject(obj: .ROOT, key: "map", ty: .Map)
        try original.put(obj: map, key: "key", value: .F64(3.5))
        try original.put(obj: .ROOT, key: "counter", value: .Counter(4))

        let rescued = try Document(rescuing: original.save())
        XCTAssertEqual(rescued.keys(obj: .ROOT), ["counter", "list", "map", "text"])
        XCTAssertEqual(try rescued.get(obj: .ROOT, key: "counter"), .Scalar(.Counter(4)))
        guard case let .Object(rescuedText, .Text) = try rescued.get(obj: .ROOT, key: "text"),
              case let .Object(rescuedList, .List) = try rescued.get(obj: .ROOT, key: "list"),
              case let .Object(rescuedMap, .Map) = try rescued.get(obj: .ROOT, key: "map")
        else {
            return XCTFail("Expected text, list and map objects")
        }
        XCTAssertEqual(try rescued.text(obj: rescuedText), "Hello marks")
        XCTAssertEqual(try rescued.marks(obj: rescuedText), [])
        XCTAssertEqual(try rescued.values(obj: rescuedList), [.Scalar(.Int(1)), .Scalar(.String("two"))])
        XCTAssertEqual(try rescued.get(obj: rescuedMap, key: "key"), .Scalar(.F64(3.5)))
    }

    func testRescuingDataThatIsNotADocumentThrows() {
        for data in [
            Data([0x00]),
            Data("not an automerge document".utf8),
            Data([0x85, 0x6F, 0x4A, 0x83, 0xFF, 0xFF, 0xFF, 0xFF]),
        ] {
            XCTAssertThrowsError(try Document(rescuing: data), "\(Array(data))") { XCTAssert($0 is LoadError, "\($0)") }
        }
    }

    func testRescuingNoDataGivesAnEmptyDocument() throws {
        let doc = try Document(rescuing: Data())
        XCTAssertEqual(doc.keys(obj: .ROOT), [])
        XCTAssertEqual(doc.getHistory(), [])
    }
}
