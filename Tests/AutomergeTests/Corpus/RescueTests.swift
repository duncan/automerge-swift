import Automerge
import Foundation
import Testing

@Suite("Rescuing documents")
struct RescueTests {
    static let brokenMark = "upstream/fixtures/broken_zero_width_mark.automerge"

    @Test("A document with a broken mark fails to load but can be rescued")
    func rescuesBrokenMark() throws {
        let data = try Corpus.data(Self.brokenMark)
        #expect(throws: LoadError.self) { try Document(data) }

        // The contents the Rust `rescue` test expects for this fixture.
        let doc = try Document(rescuing: data)
        #expect(doc.keys(obj: .ROOT) == ["o1", "text"])
        guard case let .Object(o1, .Text) = try doc.get(obj: .ROOT, key: "o1"),
              case let .Object(text, .Text) = try doc.get(obj: .ROOT, key: "text")
        else {
            Issue.record("expected text objects at `o1` and `text`")
            return
        }
        #expect(try doc.text(obj: o1) == "tsxs")
        #expect(try doc.text(obj: text) == "")
    }

    @Test("A rescued document has one change and a new actor")
    func rescuedDocumentHasOneChange() throws {
        let doc = try Document(rescuing: Corpus.data(Self.brokenMark))
        let history = doc.getHistory()
        #expect(history.count == 1)
        let change = try #require(history.first.flatMap { doc.change(hash: $0) })
        #expect(change.message == "Rescued from a document that failed to load")
        #expect(change.deps.isEmpty)
        #expect(change.actorId == doc.actor)
    }

    @Test("A rescued document saves, reloads and syncs like any other")
    func rescuedDocumentIsUsable() throws {
        let doc = try Document(rescuing: Corpus.data(Self.brokenMark))
        try doc.put(obj: .ROOT, key: "added", value: .Boolean(true))
        let reloaded = try Document(doc.save())
        #expect(try CorpusDump.contents(of: reloaded) == CorpusDump.contents(of: doc))

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
        #expect(peer.heads() == doc.heads())
        #expect(try CorpusDump.contents(of: peer) == CorpusDump.contents(of: doc))
    }

    @Test("Rescuing a valid document keeps its visible contents, without marks", arguments: GoldenRecipe.all)
    func rescuesValidDocument(recipe: GoldenRecipe) throws {
        let data = try Corpus.data("golden/\(recipe.name).automerge")
        let loaded = try Document(data)
        let rescued = try Document(rescuing: data)
        #expect(try CorpusDump.contents(of: rescued) == CorpusDump.contents(of: loaded).winners.withoutMarks)
    }

    @Test("Rescuing data that isn't a document throws", arguments: [
        Data([0x00]),
        Data("not an automerge document".utf8),
        Data([0x85, 0x6F, 0x4A, 0x83, 0xFF, 0xFF, 0xFF, 0xFF]),
    ])
    func rescuingGarbageThrows(data: Data) {
        #expect(throws: LoadError.self) { try Document(rescuing: data) }
    }

    @Test("Rescuing no data gives an empty document")
    func rescuingEmptyData() throws {
        let doc = try Document(rescuing: Data())
        #expect(doc.keys(obj: .ROOT).isEmpty)
        #expect(doc.getHistory().isEmpty)
    }
}

extension JSONValue {
    /// This dump with the marks removed from every text object.
    var withoutMarks: JSONValue {
        switch self {
        case let .object(members):
            if case var .object(text)? = members["text"], text["marks"] != nil {
                text["marks"] = .array([])
                return .object(["text": .object(text)])
            }
            return .object(members.mapValues(\.withoutMarks))
        case let .array(values):
            return .array(values.map(\.withoutMarks))
        default:
            return self
        }
    }
}
