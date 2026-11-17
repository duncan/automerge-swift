@testable import Automerge
import XCTest

class ChangeInspectionTestCase: XCTestCase {
    let alice = AuthorId(data: Data("alice".utf8))!

    /// Makes a change with a message and timestamp, and returns it.
    @discardableResult
    private func makeChange(
        _ doc: Document,
        key: String = "key",
        value: String = "value",
        message: String? = nil,
        timestamp: Date = Date(timeIntervalSince1970: 1000)
    ) throws -> Change {
        try doc.put(obj: ObjId.ROOT, key: key, value: .String(value))
        doc.commitWith(message: message, timestamp: timestamp)
        return try XCTUnwrap(doc.lastLocalChange())
    }

    // MARK: Change metadata

    func testMetadataMatchesTheChange() throws {
        let doc = Document()
        let first = try makeChange(doc, value: "one", message: "first", timestamp: Date(timeIntervalSince1970: 1000))
        let second = try makeChange(doc, value: "two", message: nil, timestamp: Date(timeIntervalSince1970: 2000))

        let firstMeta = try XCTUnwrap(doc.changeMetadata(hash: first.hash))
        XCTAssertEqual(firstMeta.hash, first.hash)
        XCTAssertEqual(firstMeta.actorId, doc.actor)
        XCTAssertNil(firstMeta.author)
        XCTAssertEqual(firstMeta.sequenceNumber, 1)
        XCTAssertEqual(firstMeta.message, "first")
        XCTAssertEqual(firstMeta.timestamp, first.timestamp)
        XCTAssertEqual(firstMeta.deps, [])
        XCTAssertEqual(firstMeta.startOp, 1)
        XCTAssertEqual(firstMeta.maxOp, 1)

        let secondMeta = try XCTUnwrap(doc.changeMetadata(hash: second.hash))
        XCTAssertEqual(secondMeta.sequenceNumber, 2)
        XCTAssertNil(secondMeta.message)
        XCTAssertEqual(secondMeta.timestamp, Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(secondMeta.deps, [first.hash])
        XCTAssertEqual(secondMeta.startOp, 2)
        XCTAssertEqual(secondMeta.maxOp, 2)
    }

    func testMetadataCoversEveryOperationInAChange() throws {
        let doc = Document()
        try doc.put(obj: ObjId.ROOT, key: "a", value: .Int(1))
        try doc.put(obj: ObjId.ROOT, key: "b", value: .Int(2))
        try doc.put(obj: ObjId.ROOT, key: "c", value: .Int(3))
        let meta = try XCTUnwrap(doc.changeMetadata().first)
        XCTAssertEqual(meta.startOp, 1)
        XCTAssertEqual(meta.maxOp, 3)
    }

    func testMetadataForAnUnknownHashIsNil() throws {
        let doc = Document()
        let other = Document()
        let change = try makeChange(other)
        XCTAssertNil(doc.changeMetadata(hash: change.hash))
    }

    func testMetadataListsChangesInHistoryOrder() throws {
        let doc = Document()
        try makeChange(doc, value: "one", message: "one")
        try makeChange(doc, value: "two", message: "two")
        try makeChange(doc, value: "three", message: "three")

        let metadata = doc.changeMetadata()
        XCTAssertEqual(metadata.map(\.hash), doc.getHistory())
        XCTAssertEqual(metadata.map(\.message), ["one", "two", "three"])
        XCTAssertEqual(metadata.map(\.sequenceNumber), [1, 2, 3])
    }

    func testMetadataOfAnEmptyDocumentIsEmpty() {
        XCTAssertEqual(Document().changeMetadata(), [])
    }

    func testMetadataIncludesAPendingChange() throws {
        let doc = Document()
        try doc.put(obj: ObjId.ROOT, key: "key", value: .String("value"))
        XCTAssertEqual(doc.changeMetadata().count, 1, "Reading the metadata commits the pending change, as getHistory does")
    }

    func testMetadataSinceHeadsLeavesOutEarlierChanges() throws {
        let doc = Document()
        try makeChange(doc, value: "one", message: "one")
        let heads = doc.heads()
        try makeChange(doc, value: "two", message: "two")
        try makeChange(doc, value: "three", message: "three")

        XCTAssertEqual(doc.changeMetadata(since: heads).map(\.message), ["two", "three"])
        XCTAssertEqual(doc.changeMetadata(since: doc.heads()), [])
    }

    func testMetadataIncludesChangesFromOtherPeers() throws {
        let doc = Document()
        try makeChange(doc, key: "a", message: "mine")
        let heads = doc.heads()

        let peer = doc.fork()
        try makeChange(peer, key: "b", message: "theirs")
        try doc.merge(other: peer)

        let added = doc.changeMetadata(since: heads)
        XCTAssertEqual(added.map(\.message), ["theirs"])
        XCTAssertEqual(added.first?.actorId, peer.actor)
    }

    func testMetadataHasTheAuthorOfEveryChange() throws {
        let doc = Document(author: alice)
        let first = try makeChange(doc, value: "one")
        let second = try makeChange(doc, value: "two")

        XCTAssertEqual(first.recordedAuthor, alice)
        XCTAssertNil(second.recordedAuthor)
        XCTAssertEqual(doc.changeMetadata().map(\.author), [alice, alice])
        XCTAssertEqual(doc.changeMetadata(hash: second.hash)?.author, alice)
    }

    func testMetadataSurvivesSavingAndLoading() throws {
        let doc = Document(author: alice)
        try makeChange(doc, value: "one", message: "one")
        try makeChange(doc, value: "two", message: "two")

        let loaded = try Document(doc.save())
        XCTAssertEqual(loaded.changeMetadata(), doc.changeMetadata())
    }

    // MARK: Last local change

    func testANewDocumentHasNoLastLocalChange() {
        XCTAssertNil(Document().lastLocalChange())
    }

    func testTheLastLocalChangeIsTheMostRecentOne() throws {
        let doc = Document()
        try makeChange(doc, value: "one", message: "one")
        try doc.put(obj: ObjId.ROOT, key: "key", value: .String("two"))

        let last = try XCTUnwrap(doc.lastLocalChange())
        XCTAssertEqual(doc.heads(), [last.hash], "A pending change is committed and returned")
        XCTAssertEqual(last.actorId, doc.actor)
        XCTAssertEqual(doc.changeMetadata(hash: last.hash)?.sequenceNumber, 2)
    }

    func testTheLastLocalChangeIgnoresChangesFromOtherPeers() throws {
        let doc = Document()
        let mine = try makeChange(doc, key: "a")

        let peer = doc.fork()
        let theirs = try makeChange(peer, key: "b")
        try doc.merge(other: peer)

        XCTAssertEqual(doc.heads(), [theirs.hash])
        XCTAssertEqual(doc.lastLocalChange(), mine)
    }

    func testTheLastLocalChangeCanBeAppliedToAnotherDocument() throws {
        let doc = Document()
        let change = try makeChange(doc)

        let other = Document()
        try other.applyEncodedChanges(encoded: change.bytes)
        XCTAssertEqual(other.heads(), doc.heads())
        XCTAssertNil(other.lastLocalChange(), "The other document didn't make the change")
    }

    // MARK: Missing dependencies

    func testACompleteDocumentHasNoMissingDependencies() throws {
        let doc = Document()
        XCTAssertEqual(doc.missingDependencies(), [])
        try makeChange(doc)
        XCTAssertEqual(doc.missingDependencies(), [])
        XCTAssertEqual(doc.missingDependencies(heads: doc.heads()), [])
    }

    func testAChangeReceivedBeforeItsDependencyIsMissingIt() throws {
        let doc = Document()
        let first = try makeChange(doc, value: "one")
        let second = try makeChange(doc, value: "two")

        let other = Document()
        try other.applyEncodedChanges(encoded: second.bytes)
        XCTAssertEqual(other.heads(), [], "The change waits for the one it depends upon")
        XCTAssertEqual(other.missingDependencies(), [first.hash])

        try other.applyEncodedChanges(encoded: first.bytes)
        XCTAssertEqual(other.missingDependencies(), [])
        XCTAssertEqual(other.heads(), doc.heads())
    }

    func testHeadsTheDocumentDoesntHaveAreMissing() throws {
        let doc = Document()
        try makeChange(doc, key: "a")
        let peer = doc.fork()
        let theirs = try makeChange(peer, key: "b")

        XCTAssertEqual(doc.missingDependencies(heads: peer.heads()), [theirs.hash])
        try doc.merge(other: peer)
        XCTAssertEqual(doc.missingDependencies(heads: peer.heads()), [])
    }

    // MARK: Decoding a change

    func testAChangeDecodesFromItsBytes() throws {
        let doc = Document(author: alice)
        let change = try makeChange(doc, message: "hello")

        let decoded = try Change(bytes: change.bytes)
        XCTAssertEqual(decoded, change)
        XCTAssertEqual(decoded.message, "hello")
        XCTAssertEqual(decoded.actorId, doc.actor)
        XCTAssertEqual(decoded.recordedAuthor, alice)
    }

    func testDecodingInvalidBytesThrows() {
        XCTAssertThrowsError(try Change(bytes: Data([1, 2, 3]))) { error in
            XCTAssertTrue(error is DecodeChangeError, "\(error)")
            XCTAssertNotNil((error as? DecodeChangeError)?.errorDescription)
        }
        XCTAssertThrowsError(try Change(bytes: Data())) { error in
            XCTAssertTrue(error is DecodeChangeError, "\(error)")
        }
    }

    func testDecodingASavedDocumentThrows() throws {
        let doc = Document()
        try makeChange(doc)
        XCTAssertThrowsError(try Change(bytes: doc.save())) { error in
            XCTAssertTrue(error is DecodeChangeError, "\(error)")
        }
    }
}
