import Automerge
import Foundation
import Testing

/// Fixtures copied from the Rust `automerge` crate's own test suite (`rust/automerge/tests`), run
/// through the Swift API so that a crash, or a change in what loads, shows up here as well as upstream.
@Suite("Upstream corpus")
struct UpstreamCorpusTests {
    /// Inputs the Rust fuzzer found crashing earlier versions of automerge, and the reason each is rejected.
    static let crashers: [(name: String, reason: String)] = [
        ("action-is-48.automerge", "unrecognized action index 48"),
        ("crash-da39a3ee5e6b4b0d3255bfef95601890afd80709", "not enough data"),
        ("incorrect_max_op.automerge", "mismatching heads"),
        ("invalid_deflate_stream.automerge", "corrupt deflate stream"),
        ("missing_actor.automerge", "missing actor or counter"),
        ("overflow_in_length.automerge", "columns were not in normalized order"),
        ("too_many_deps.automerge", "failed to fill whole buffer"),
        ("too_many_ops.automerge", "counter out of range"),
    ]

    /// Well-formed documents that must be rejected, and the reason each is rejected.
    static let invalidFixtures: [(name: String, reason: String)] = [
        // The value metadata says the counter is two bytes, but its LEB128 encoding is one byte
        // followed by an extra zero.
        ("counter_value_has_incorrect_meta.automerge", "extra bytes"),
        // The counter's LEB128 encoding uses two bytes where one would do.
        ("counter_value_is_overlong.automerge", "leb128 was improperly encoded"),
        // Object IDs with 64-bit counters, as a change chunk and as a document chunk. The Rust test
        // accepts either loading or rejecting these; automerge 0.7 rejects both.
        ("64bit_obj_id_change.automerge", "counter too large"),
        ("64bit_obj_id_doc.automerge", "counter out of range"),
    ]

    /// Documents containing a map at `a` with `a: "b"` inside it, stored as two change chunks.
    static let twoChangeChunks = [
        "two_change_chunks.automerge",
        "two_change_chunks_compressed.automerge",
        "two_change_chunks_out_of_order.automerge",
    ]

    static let validFixtures = twoChangeChunks + ["counter_value_is_ok.automerge"]

    @Test("Every file in the corpus has an expectation")
    func corpusIsFullyRegistered() throws {
        #expect(try Corpus.fileNames(in: "upstream/fuzz-crashers") == Self.crashers.map(\.name).sorted())
        #expect(
            try Corpus.fileNames(in: "upstream/fixtures")
                == (Self.invalidFixtures.map(\.name) + Self.validFixtures).sorted()
        )
    }

    @Test("Fuzz crashers are rejected when loaded", arguments: crashers)
    func crasherIsRejectedByLoad(name: String, reason: String) throws {
        let data = try Corpus.data("upstream/fuzz-crashers/\(name)")
        let error = #expect(throws: LoadError.self) { try Document(data) }
        #expect(error?.localizedDescription.contains(reason) == true, "\(String(describing: error))")
    }

    @Test("Fuzz crashers are rejected when applied as changes", arguments: crashers.map(\.name))
    func crasherIsRejectedByApply(name: String) throws {
        let data = try Corpus.data("upstream/fuzz-crashers/\(name)")
        let doc = Document()
        #expect(throws: DocError.self) { try doc.applyEncodedChanges(encoded: data) }
        #expect(doc.heads().isEmpty)
        #expect(try doc.keys(obj: .ROOT).isEmpty)
    }

    @Test("Invalid fixtures are rejected", arguments: invalidFixtures)
    func invalidFixtureIsRejected(name: String, reason: String) throws {
        let data = try Corpus.data("upstream/fixtures/\(name)")
        let error = #expect(throws: LoadError.self) { try Document(data) }
        #expect(error?.localizedDescription.contains(reason) == true, "\(String(describing: error))")
    }

    @Test("Two change chunks load in any form", arguments: twoChangeChunks)
    func twoChangeChunksLoad(name: String) throws {
        let doc = try Document(Corpus.data("upstream/fixtures/\(name)"))
        guard case let .Object(map, .Map) = try doc.get(obj: .ROOT, key: "a") else {
            Issue.record("expected a map at `a`")
            return
        }
        #expect(try doc.get(obj: map, key: "a") == .Scalar(.String("b")))
        #expect(try doc.keys(obj: .ROOT) == ["a"])
        #expect(try doc.keys(obj: map) == ["a"])
    }

    @Test("A minimally encoded counter loads")
    func counterValueLoads() throws {
        let doc = try Document(Corpus.data("upstream/fixtures/counter_value_is_ok.automerge"))
        #expect(try doc.get(obj: .ROOT, key: "a") == .Scalar(.Counter(2000)))
    }

    @Test("Valid fixtures survive a save and reload", arguments: validFixtures)
    func validFixtureRoundTrips(name: String) throws {
        let original = try Document(Corpus.data("upstream/fixtures/\(name)"))
        let saved = original.save()
        let reloaded = try Document(saved)
        #expect(reloaded.heads() == original.heads())
        #expect(reloaded.save() == saved)

        // Loading the bytes as changes into an empty document produces the same history.
        let applied = Document()
        try applied.applyEncodedChanges(encoded: Corpus.data("upstream/fixtures/\(name)"))
        #expect(applied.heads() == original.heads())
        #expect(applied.save() == saved)
    }
}
