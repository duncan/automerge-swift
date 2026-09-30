import Automerge
import Foundation
import Testing

/// Documents built by ``GoldenRecipe``, checked in as saved bytes with a typed JSON dump of their
/// contents and history.
///
/// The checked-in bytes must still load to the expected contents, and building each recipe today must
/// still save to the checked-in bytes. A failure in the first direction means documents saved by an
/// earlier version no longer load the same way; a failure only in the second means the saved format
/// changed, which is worth understanding before regenerating the corpus.
///
/// To regenerate after an intended change, run the tests with `AUTOMERGE_UPDATE_CORPUS=1` set,
/// which rewrites the files in the source tree instead of comparing against them, then review the
/// diff:
///
/// ```bash
/// AUTOMERGE_UPDATE_CORPUS=1 swift test --filter GoldenCorpusTests
/// ```
@Suite("Golden corpus")
struct GoldenCorpusTests {
    static let updating = ProcessInfo.processInfo.environment["AUTOMERGE_UPDATE_CORPUS"] != nil

    @Test("Regenerate the golden corpus", .enabled(if: updating))
    func regenerate() throws {
        let golden = Self.sourceDirectory.appendingPathComponent("golden")
        for recipe in GoldenRecipe.all {
            let doc = try recipe.build()
            try doc.save().write(to: golden.appendingPathComponent("\(recipe.name).automerge"))
            try Data(CorpusDump.json(for: doc).rendered.utf8)
                .write(to: golden.appendingPathComponent("\(recipe.name).json"))
        }
        let exemplar = try Document(Corpus.data("interop/exemplar"))
        try Data(CorpusDump.json(for: exemplar).rendered.utf8)
            .write(to: Self.sourceDirectory.appendingPathComponent("interop/exemplar.json"))
    }

    @Test("Every file in the golden corpus has a recipe", .disabled(if: updating))
    func corpusIsFullyRegistered() throws {
        let expected = GoldenRecipe.all.flatMap { ["\($0.name).automerge", "\($0.name).json"] }
        #expect(try Corpus.fileNames(in: "golden") == expected.sorted())
    }

    @Test("Checked-in documents load to the expected contents", .disabled(if: updating),
          arguments: GoldenRecipe.all)
    func checkedInDocumentLoads(recipe: GoldenRecipe) throws {
        let doc = try Document(Corpus.data("golden/\(recipe.name).automerge"))
        #expect(try CorpusDump.json(for: doc).rendered == Self.expectedJSON(recipe))
    }

    @Test("Checked-in documents load the same when applied as changes", .disabled(if: updating),
          arguments: GoldenRecipe.all)
    func checkedInDocumentApplies(recipe: GoldenRecipe) throws {
        let doc = Document()
        try doc.applyEncodedChanges(encoded: Corpus.data("golden/\(recipe.name).automerge"))
        #expect(try CorpusDump.json(for: doc).rendered == Self.expectedJSON(recipe))
    }

    @Test("Checked-in documents save back to the same bytes", .disabled(if: updating),
          arguments: GoldenRecipe.all)
    func checkedInDocumentRoundTrips(recipe: GoldenRecipe) throws {
        let bytes = try Corpus.data("golden/\(recipe.name).automerge")
        #expect(try Document(bytes).save() == bytes)
    }

    @Test("Recipes build the checked-in documents", .disabled(if: updating), arguments: GoldenRecipe.all)
    func recipeBuildsCheckedInDocument(recipe: GoldenRecipe) throws {
        let doc = try recipe.build()
        // Compare the contents first: a difference there is easier to read than one in the bytes.
        #expect(try CorpusDump.json(for: doc).rendered == Self.expectedJSON(recipe))
        #expect(try doc.save() == Corpus.data("golden/\(recipe.name).automerge"))
    }

    @Test("The interop exemplar loads to the expected contents", .disabled(if: updating))
    func exemplarLoads() throws {
        let doc = try Document(Corpus.data("interop/exemplar"))
        let expected = try String(decoding: Corpus.data("interop/exemplar.json"), as: UTF8.self)
        #expect(try CorpusDump.json(for: doc).rendered == expected)
    }

    @Test("The interop exemplar matches `automerge export` from the Rust CLI")
    func exemplarMatchesRustExport() throws {
        let doc = try Document(Corpus.data("interop/exemplar"))
        let expected = try String(decoding: Corpus.data("interop/exemplar.export.json"), as: UTF8.self)
        #expect(try CorpusDump.exportJSON(for: doc).rendered == expected)
    }

    private static func expectedJSON(_ recipe: GoldenRecipe) throws -> String {
        try String(decoding: Corpus.data("golden/\(recipe.name).json"), as: UTF8.self)
    }

    /// `Fixtures/Corpus` in the source tree, which regeneration writes to. Tests read the copy in the
    /// test bundle instead, through ``Corpus``.
    private static var sourceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Corpus")
    }
}
