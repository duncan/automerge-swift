import Automerge
import XCTest

class AuthorsTestCase: XCTestCase {
    let alice = AuthorId(data: Data("alice".utf8))!
    let bob = AuthorId(data: Data("bob".utf8))!

    /// Makes a change and returns it.
    private func makeChange(_ doc: Document, key: String = "key", value: String = "value") throws -> Change {
        try doc.put(obj: ObjId.ROOT, key: key, value: .String(value))
        let hash = try XCTUnwrap(doc.heads().first)
        return try XCTUnwrap(doc.change(hash: hash))
    }

    func testAnAuthorIdCantBeEmpty() {
        XCTAssertNil(AuthorId(data: Data()))
        XCTAssertEqual(alice.data, Data("alice".utf8))
        XCTAssertEqual(alice.description, "616C696365")
    }

    func testADocumentHasNoAuthorUntilOneIsSet() throws {
        let doc = Document()
        XCTAssertNil(doc.author)
        let change = try makeChange(doc)
        XCTAssertNil(change.author)
        XCTAssertNil(doc.author(for: doc.actor))
        XCTAssertEqual(doc.authors, [])
    }

    func testTheFirstChangeRecordsTheAuthor() throws {
        let doc = Document()
        doc.author = alice
        XCTAssertEqual(doc.author, alice)
        XCTAssertEqual(doc.authors, [], "The author isn't recorded until a change is")

        let change = try makeChange(doc)
        XCTAssertEqual(change.author, alice)
        XCTAssertEqual(change.actorId, doc.actor)
        XCTAssertEqual(doc.author(for: doc.actor), alice)
        XCTAssertEqual(doc.authors, [alice])
        XCTAssertEqual(doc.actors(for: alice), [doc.actor])
        XCTAssertEqual(doc.actors(for: bob), [])
    }

    func testOnlyAnActorsFirstChangeCarriesTheAuthor() throws {
        let doc = Document()
        doc.author = alice
        let first = try makeChange(doc, value: "one")
        let second = try makeChange(doc, value: "two")

        XCTAssertEqual(first.author, alice)
        XCTAssertNil(second.author)
        XCTAssertEqual(doc.author(for: second.actorId), alice, "The actor's author covers all its changes")
    }

    func testSettingADifferentAuthorGivesTheDocumentANewActor() throws {
        let doc = Document()
        let original = doc.actor
        doc.author = alice
        let alicesActor = doc.actor
        XCTAssertNotEqual(alicesActor, original)

        doc.author = alice
        XCTAssertEqual(doc.actor, alicesActor, "Setting the same author keeps the actor")

        doc.author = bob
        XCTAssertNotEqual(doc.actor, alicesActor)
        doc.author = nil
        XCTAssertNil(doc.author)
    }

    func testSettingTheAuthorAndThenTheActorKeepsTheChosenActor() throws {
        let chosen = ActorId()
        let doc = Document()
        doc.author = alice
        doc.actor = chosen

        let change = try makeChange(doc)
        XCTAssertEqual(doc.actor, chosen)
        XCTAssertEqual(change.actorId, chosen)
        XCTAssertEqual(change.author, alice)
        XCTAssertEqual(doc.author(for: chosen), alice)
    }

    func testSettingTheActorAndThenTheAuthorReplacesTheChosenActor() throws {
        let chosen = ActorId()
        let doc = Document()
        doc.actor = chosen
        doc.author = alice

        let change = try makeChange(doc)
        XCTAssertNotEqual(change.actorId, chosen)
        XCTAssertEqual(change.author, alice)
    }

    func testAnActorThatHasMadeAChangeKeepsNoAuthor() throws {
        let chosen = ActorId()
        let doc = Document()
        doc.actor = chosen
        _ = try makeChange(doc, value: "one")

        doc.author = alice
        doc.actor = chosen
        let change = try makeChange(doc, value: "two")

        XCTAssertEqual(change.actorId, chosen)
        XCTAssertNil(change.author, "Only an actor's first change records an author")
        XCTAssertNil(doc.author(for: chosen))
    }

    func testSettingTheAuthorCommitsPendingChangesWithThePreviousActor() throws {
        let doc = Document()
        let original = doc.actor
        try doc.put(obj: ObjId.ROOT, key: "key", value: .String("before"))
        doc.author = alice
        _ = try makeChange(doc, value: "after")

        let actors = doc.getHistory().compactMap { doc.change(hash: $0)?.actorId }
        XCTAssertEqual(actors, [original, doc.actor])
        XCTAssertNil(doc.author(for: original))
        XCTAssertEqual(doc.author(for: doc.actor), alice)
    }

    func testAuthorsSurviveSavingAndLoading() throws {
        let doc = Document()
        doc.author = alice
        _ = try makeChange(doc, value: "one")
        _ = try makeChange(doc, value: "two")
        let alicesActor = doc.actor
        doc.author = bob
        _ = try makeChange(doc, value: "three")
        let bobsActor = doc.actor

        // save() compacts the changes into a single document chunk.
        let loaded = try Document(doc.save())
        XCTAssertNil(loaded.author, "A loaded document has no author until one is set")
        XCTAssertEqual(loaded.authors, [alice, bob])
        XCTAssertEqual(loaded.author(for: alicesActor), alice)
        XCTAssertEqual(loaded.author(for: bobsActor), bob)
        XCTAssertEqual(loaded.actors(for: alice), [alicesActor])

        let authors = loaded.getHistory().map { loaded.change(hash: $0)?.author }
        XCTAssertEqual(authors, [alice, nil, bob])
    }

    func testAuthorsSurviveIncrementalChanges() throws {
        let doc = Document()
        doc.author = alice
        _ = try makeChange(doc)

        let other = Document()
        try other.applyEncodedChanges(encoded: doc.encodeNewChanges())
        XCTAssertEqual(other.authors, [alice])
        XCTAssertEqual(other.author(for: doc.actor), alice)
    }

    func testAuthorsCarryAcrossAMerge() throws {
        let doc = Document()
        doc.author = alice
        _ = try makeChange(doc, key: "a")

        let copy = doc.fork()
        copy.author = bob
        _ = try makeChange(copy, key: "b")

        try doc.merge(other: copy)
        XCTAssertEqual(doc.authors, [alice, bob])
        XCTAssertEqual(doc.author(for: copy.actor), bob)
        XCTAssertEqual(doc.actors(for: bob), [copy.actor])
    }

    func testAForkKeepsTheAuthorWithItsOwnActor() throws {
        let doc = Document()
        doc.author = alice
        _ = try makeChange(doc)

        let copy = doc.fork()
        XCTAssertNotEqual(copy.actor, doc.actor)
        XCTAssertEqual(copy.author, alice)
        let change = try makeChange(copy, key: "other")
        XCTAssertEqual(change.author, alice)
        XCTAssertEqual(Set(copy.actors(for: alice)), [doc.actor, copy.actor])
    }

    func testAForkAtEarlierHeadsHasNoAuthorUntilOneIsSet() throws {
        let doc = Document()
        doc.author = alice
        _ = try makeChange(doc)

        let copy = try doc.forkAt(heads: doc.heads())
        XCTAssertNotEqual(copy.actor, doc.actor)
        XCTAssertNil(copy.author)
        XCTAssertEqual(copy.authors, [alice], "The copy keeps the authors its changes record")
        let change = try makeChange(copy, key: "other")
        XCTAssertNil(change.author)
    }

    func testOneActorCantRecordTwoAuthors() throws {
        let shared = ActorId()
        let first = Document()
        first.author = alice
        first.actor = shared
        _ = try makeChange(first, value: "alice")

        let second = Document()
        second.author = bob
        second.actor = shared
        _ = try makeChange(second, value: "bob")

        // Automerge records an author only with an actor's first change, so two authors for one actor means two
        // first changes for it, which the merge rejects as a duplicate sequence number.
        XCTAssertThrowsError(try first.merge(other: second))
        XCTAssertEqual(first.author(for: shared), alice)
        XCTAssertEqual(first.authors, [alice])
    }
}
