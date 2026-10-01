@testable import Automerge
import AutomergeUtilities
import Foundation
import Testing

/// The `…At(heads:)` APIs, which read a document as it was at earlier heads.
@Suite("Reading at earlier heads")
struct HistoryContractTests {
    /// A document edited in three commits, with the heads after each.
    struct History {
        let doc = Document()
        let list: ObjId
        let text: ObjId
        let first: Set<ChangeHash>
        let second: Set<ChangeHash>
        let third: Set<ChangeHash>

        init() throws {
            list = try doc.putObject(obj: .ROOT, key: "list", ty: .List)
            try doc.insert(obj: list, index: 0, value: .String("a"))
            text = try doc.putObject(obj: .ROOT, key: "text", ty: .Text)
            try doc.spliceText(obj: text, start: 0, delete: 0, value: "hello")
            try doc.put(obj: .ROOT, key: "status", value: .String("draft"))
            doc.commitWith(message: "first", timestamp: Date(timeIntervalSince1970: 0))
            first = doc.heads()

            try doc.insert(obj: list, index: 1, value: .String("b"))
            try doc.spliceText(obj: text, start: 5, delete: 0, value: " world")
            try doc.mark(obj: text, start: 0, end: 5, expand: .none, name: "bold", value: .Boolean(true))
            try doc.put(obj: .ROOT, key: "status", value: .String("review"))
            try doc.put(obj: .ROOT, key: "added", value: .Int(1))
            doc.commitWith(message: "second", timestamp: Date(timeIntervalSince1970: 1))
            second = doc.heads()

            try doc.delete(obj: list, index: 0)
            try doc.spliceText(obj: text, start: 0, delete: 6)
            try doc.delete(obj: .ROOT, key: "added")
            try doc.put(obj: .ROOT, key: "status", value: .String("published"))
            doc.commitWith(message: "third", timestamp: Date(timeIntervalSince1970: 2))
            third = doc.heads()
        }
    }

    @Test("Every read at earlier heads sees the document as it was")
    func readsAtEarlierHeads() throws {
        let h = try History()
        let doc = h.doc

        #expect(try doc.getAt(obj: .ROOT, key: "status", heads: h.first) == .Scalar(.String("draft")))
        #expect(try doc.getAt(obj: .ROOT, key: "status", heads: h.second) == .Scalar(.String("review")))
        #expect(try doc.getAllAt(obj: .ROOT, key: "added", heads: h.second) == [.Scalar(.Int(1))])
        #expect(try doc.getAllAt(obj: .ROOT, key: "added", heads: h.third).isEmpty)
        #expect(doc.keysAt(obj: .ROOT, heads: h.first) == ["list", "status", "text"])
        #expect(doc.keysAt(obj: .ROOT, heads: h.second) == ["added", "list", "status", "text"])
        #expect(try doc.mapEntriesAt(obj: .ROOT, heads: h.second).map(\.0) == ["added", "list", "status", "text"])

        #expect(doc.lengthAt(obj: h.list, heads: h.first) == 1)
        #expect(doc.lengthAt(obj: h.list, heads: h.second) == 2)
        #expect(try doc.valuesAt(obj: h.list, heads: h.second) == [.Scalar(.String("a")), .Scalar(.String("b"))])
        #expect(try doc.getAt(obj: h.list, index: 0, heads: h.second) == .Scalar(.String("a")))
        #expect(try doc.getAllAt(obj: h.list, index: 1, heads: h.second) == [.Scalar(.String("b"))])

        #expect(try doc.textAt(obj: h.text, heads: h.first) == "hello")
        #expect(try doc.textAt(obj: h.text, heads: h.second) == "hello world")
        #expect(try doc.textAt(obj: h.text, heads: h.third) == "world")
        #expect(try doc.marksAt(obj: h.text, heads: h.first).isEmpty)
        #expect(try doc.marksAt(obj: h.text, heads: h.second) == [
            Mark(start: 0, end: 5, name: "bold", value: .Boolean(true)),
        ])
        #expect(try doc.marksAt(obj: h.text, position: .index(2), heads: h.second) == [
            Mark(start: 2, end: 2, name: "bold", value: .Boolean(true)),
        ])
    }

    @Test("Reading at the current heads matches reading the document")
    func readsAtCurrentHeads() throws {
        let h = try History()
        let doc = h.doc
        #expect(doc.keysAt(obj: .ROOT, heads: h.third) == doc.keys(obj: .ROOT))
        #expect(try doc.valuesAt(obj: h.list, heads: h.third) == doc.values(obj: h.list))
        #expect(try doc.textAt(obj: h.text, heads: h.third) == doc.text(obj: h.text))
        #expect(try doc.marksAt(obj: h.text, heads: h.third) == doc.marks(obj: h.text))
    }

    @Test("A fork at earlier heads has that version's contents and history")
    func forkAtEarlierHeads() throws {
        let h = try History()
        let fork = try h.doc.forkAt(heads: h.second)
        #expect(fork.heads() == h.second)
        #expect(fork.getHistory().count == 2)
        #expect(try fork.get(obj: .ROOT, key: "status") == .Scalar(.String("review")))
        #expect(try fork.text(obj: h.text) == "hello world")
        #expect(try fork.values(obj: h.list) == h.doc.valuesAt(obj: h.list, heads: h.second))
    }

    @Test("The difference between heads lists exactly what changed, in either direction")
    func differenceBetweenHeads() throws {
        let h = try History()
        let listPath = [PathElement(obj: .ROOT, prop: .Key("list"))]
        let textPath = [PathElement(obj: .ROOT, prop: .Key("text"))]

        #expect(h.doc.difference(from: h.first, to: h.second) == [
            Patch(action: .Put(.ROOT, .Key("added"), .Scalar(.Int(1))), path: []),
            Patch(action: .Put(.ROOT, .Key("status"), .Scalar(.String("review"))), path: []),
            Patch(action: .Insert(obj: h.list, index: 1, values: [.Scalar(.String("b"))]), path: listPath),
            Patch(action: .Marks(h.text, [Mark(start: 0, end: 5, name: "bold", value: .Boolean(true))]), path: textPath),
            Patch(action: .SpliceText(obj: h.text, index: 5, value: " world", marks: [:]), path: textPath),
        ])

        #expect(h.doc.difference(from: h.second, to: h.third) == [
            Patch(action: .DeleteMap(.ROOT, "added"), path: []),
            Patch(action: .Put(.ROOT, .Key("status"), .Scalar(.String("published"))), path: []),
            Patch(action: .DeleteSeq(DeleteSeq(obj: h.list, index: 0, length: 1)), path: listPath),
            Patch(action: .DeleteSeq(DeleteSeq(obj: h.text, index: 0, length: 6)), path: textPath),
        ])

        // Going backwards undoes each of those. The restored text comes back as two splices, because
        // only "hello" was bold.
        #expect(h.doc.difference(from: h.third, to: h.second) == [
            Patch(action: .Put(.ROOT, .Key("added"), .Scalar(.Int(1))), path: []),
            Patch(action: .Put(.ROOT, .Key("status"), .Scalar(.String("review"))), path: []),
            Patch(action: .Insert(obj: h.list, index: 0, values: [.Scalar(.String("a"))]), path: listPath),
            Patch(
                action: .SpliceText(obj: h.text, index: 0, value: "hello", marks: ["bold": .Scalar(.Boolean(true))]),
                path: textPath
            ),
            Patch(action: .SpliceText(obj: h.text, index: 5, value: " ", marks: [:]), path: textPath),
        ])

        #expect(h.doc.difference(from: h.third, to: h.third).isEmpty)
        // `since` and `to` are shorthand for differences from and to the current heads.
        #expect(h.doc.difference(since: h.second) == h.doc.difference(from: h.second, to: h.third))
        #expect(h.doc.difference(to: h.second) == h.doc.difference(from: h.third, to: h.second))
    }

    @Test("Empty heads read as an empty document")
    func emptyHeads() throws {
        let h = try History()
        #expect(h.doc.keysAt(obj: .ROOT, heads: []).isEmpty)
        #expect(h.doc.lengthAt(obj: h.list, heads: []) == 0)
        #expect(try h.doc.getAt(obj: .ROOT, key: "status", heads: []) == nil)
    }

    /// Heads that aren't in the document, such as another document's heads, are an easy mistake to
    /// make. `forkAt` rejects them, but the reads treat them like empty heads and return nothing.
    @Test("Unknown heads: forkAt throws, and reads find nothing")
    func unknownHeads() throws {
        let h = try History()
        let other = Document()
        try other.put(obj: .ROOT, key: "status", value: .String("other"))
        let unknown = other.heads()

        #expect(throws: DocError.self) { try h.doc.forkAt(heads: unknown) }
        #expect(h.doc.keysAt(obj: .ROOT, heads: unknown).isEmpty)
        #expect(h.doc.lengthAt(obj: h.list, heads: unknown) == 0)
        #expect(try h.doc.getAt(obj: .ROOT, key: "status", heads: unknown) == nil)
        #expect(try h.doc.valuesAt(obj: h.list, heads: unknown).isEmpty)
        #expect(try h.doc.textAt(obj: h.text, heads: unknown) == "")
        #expect(try h.doc.marksAt(obj: h.text, heads: unknown).isEmpty)
    }
}

@Suite("Equivalent contents")
struct EquivalentContentsTests {
    @Test("A fork has equivalent contents until one side changes")
    func forkIsEquivalent() throws {
        let doc = try ContractFixture().doc
        let fork = doc.fork()
        #expect(doc.equivalentContents(fork))
        try fork.put(obj: .ROOT, key: "string", value: .String("changed"))
        #expect(!doc.equivalentContents(fork))
    }

    @Test("Documents with the same contents but different histories are equivalent")
    func differentHistoriesAreEquivalent() throws {
        let direct = Document()
        try direct.put(obj: .ROOT, key: "key", value: .String("final"))
        let edited = Document()
        try edited.put(obj: .ROOT, key: "key", value: .String("first"))
        try edited.put(obj: .ROOT, key: "other", value: .Int(1))
        try edited.delete(obj: .ROOT, key: "other")
        try edited.put(obj: .ROOT, key: "key", value: .String("final"))
        #expect(direct.equivalentContents(edited))
        #expect(edited.equivalentContents(direct))
    }

    @Test("Text and a string with the same characters aren't equivalent")
    func textIsNotString() throws {
        let withText = Document()
        let text = try withText.putObject(obj: .ROOT, key: "key", ty: .Text)
        try withText.spliceText(obj: text, start: 0, delete: 0, value: "same")
        let withString = Document()
        try withString.put(obj: .ROOT, key: "key", value: .String("same"))
        #expect(!withText.equivalentContents(withString))
    }

    @Test("Every golden corpus document is equivalent to itself reloaded", arguments: GoldenRecipe.all)
    func goldenDocumentIsEquivalentToReload(recipe: GoldenRecipe) throws {
        let data = try Corpus.data("golden/\(recipe.name).automerge")
        #expect(try Document(data).equivalentContents(Document(data)))
    }
}

@Suite("Scalar edge values")
struct ScalarEdgeValueTests {
    static let values: [ScalarValue] = [
        .Int(.min), .Int(.max), .Uint(.max), .Uint(0),
        .F64(-0.0), .F64(.infinity), .F64(-.infinity), .F64(.leastNonzeroMagnitude), .F64(.greatestFiniteMagnitude),
        .String(""), .String("nul \u{0} and 🇬🇧"), .Bytes(Data()), .Bytes(Data(repeating: 0xFF, count: 1024)),
        .Timestamp(Date(timeIntervalSince1970: -1.5)), .Timestamp(Date(timeIntervalSince1970: 0)),
        .Counter(.min), .Counter(.max), .Boolean(false), .Null,
    ]

    @Test("Values round-trip through put, save and load", arguments: values)
    func roundTrips(value: ScalarValue) throws {
        let doc = Document()
        try doc.put(obj: .ROOT, key: "value", value: value)
        #expect(try doc.get(obj: .ROOT, key: "value") == .Scalar(value))
        #expect(try Document(doc.save()).get(obj: .ROOT, key: "value") == .Scalar(value))
    }

    @Test("-0.0 keeps its sign")
    func negativeZeroKeepsSign() throws {
        let doc = Document()
        try doc.put(obj: .ROOT, key: "value", value: .F64(-0.0))
        guard case let .Scalar(.F64(value))? = try Document(doc.save()).get(obj: .ROOT, key: "value") else {
            Issue.record("expected a double")
            return
        }
        #expect(value.sign == .minus)
    }

    @Test("NaN round-trips")
    func nanRoundTrips() throws {
        let doc = Document()
        try doc.put(obj: .ROOT, key: "value", value: .F64(.nan))
        guard case let .Scalar(.F64(value))? = try Document(doc.save()).get(obj: .ROOT, key: "value") else {
            Issue.record("expected a double")
            return
        }
        #expect(value.isNaN)
    }

    @Test("Timestamps keep millisecond precision, rounding toward zero")
    func timestampPrecision() throws {
        let doc = Document()
        try doc.put(obj: .ROOT, key: "positive", value: .Timestamp(Date(timeIntervalSince1970: 1.0019)))
        try doc.put(obj: .ROOT, key: "negative", value: .Timestamp(Date(timeIntervalSince1970: -1.0019)))
        let positive = try doc.get(obj: .ROOT, key: "positive")
        let negative = try doc.get(obj: .ROOT, key: "negative")
        #expect(positive == .Scalar(.Timestamp(Date(timeIntervalSince1970: 1.001))))
        #expect(negative == .Scalar(.Timestamp(Date(timeIntervalSince1970: -1.001))))
    }

    @Test("Incrementing a counter past its range")
    func counterOverflow() throws {
        let doc = Document()
        try doc.put(obj: .ROOT, key: "count", value: .Counter(.max))
        try doc.increment(obj: .ROOT, key: "count", by: 1)
        let value = try doc.get(obj: .ROOT, key: "count")
        #expect(value == .Scalar(.Counter(.min)))
    }
}
