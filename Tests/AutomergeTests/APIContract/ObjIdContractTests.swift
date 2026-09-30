import Automerge
import Foundation
import Testing

/// Object IDs that don't belong to the document, or whose object has been deleted.
@Suite("Foreign and deleted objects")
struct ObjIdContractTests {
    static let foreignOperations: [NamedOperation] = [
        NamedOperation("get") { f in _ = try f.doc.get(obj: f.foreign(), key: "k") },
        NamedOperation("put") { f in try f.doc.put(obj: f.foreign(), key: "k", value: .Int(1)) },
        NamedOperation("putObject") { f in _ = try f.doc.putObject(obj: f.foreign(), key: "k", ty: .Map) },
        NamedOperation("delete") { f in try f.doc.delete(obj: f.foreign(), key: "k") },
        NamedOperation("text") { f in _ = try f.doc.text(obj: f.foreign()) },
        NamedOperation("path") { f in _ = try f.doc.path(obj: f.foreign()) },
    ]

    @Test("An object from another document is rejected", arguments: foreignOperations)
    func foreignObjectRejected(operation: NamedOperation) throws {
        let fixture = try ContractFixture()
        try fixture.expectRejected({ $0.isInternal(containing: "invalid obj id") }, operation.run)
    }

    @Test("Non-throwing reads of an object from another document find nothing")
    func foreignObjectNonThrowingReads() throws {
        let fixture = try ContractFixture()
        let foreign = try fixture.foreign()
        // These can't report an error, so they return what they'd return for an empty object.
        #expect(fixture.doc.keys(obj: foreign).isEmpty)
        #expect(fixture.doc.length(obj: foreign) == 0)
        #expect(fixture.doc.keysAt(obj: foreign, heads: fixture.doc.heads()).isEmpty)
    }

    @Test("A deleted object keeps its contents, and can still be read and written")
    func deletedObjectIsStillUsable() throws {
        let fixture = try ContractFixture()
        try fixture.doc.delete(obj: .ROOT, key: "map")

        #expect(try fixture.doc.get(obj: .ROOT, key: "map") == nil)
        #expect(try fixture.doc.get(obj: fixture.map, key: "k") == .Scalar(.Int(1)))
        #expect(fixture.doc.keys(obj: fixture.map) == ["k"])
        // Writes to a deleted object succeed, but nothing reachable from the root sees them.
        try fixture.doc.put(obj: fixture.map, key: "k", value: .Int(2))
        #expect(try fixture.doc.get(obj: fixture.map, key: "k") == .Scalar(.Int(2)))
        #expect(try CorpusDump.contents(of: fixture.doc) == CorpusDump.contents(of: Document(fixture.doc.save())))
        // Its path is where it was before it was deleted.
        #expect(try fixture.doc.path(obj: fixture.map) == [PathElement(obj: .ROOT, prop: .Key("map"))])
    }

    @Test("An object read at heads from before it existed is empty")
    func objectBeforeItExisted() throws {
        let fixture = try ContractFixture()
        let before = fixture.doc.heads()
        let late = try fixture.doc.putObject(obj: .ROOT, key: "late", ty: .Map)
        try fixture.doc.put(obj: late, key: "k", value: .Int(2))

        #expect(try fixture.doc.getAt(obj: late, key: "k", heads: before) == nil)
        #expect(fixture.doc.keysAt(obj: late, heads: before).isEmpty)
        #expect(fixture.doc.lengthAt(obj: late, heads: before) == 0)
    }
}

extension ContractFixture {
    /// A map from another document.
    func foreign() throws -> ObjId {
        let other = Document()
        let map = try other.putObject(obj: .ROOT, key: "map", ty: .Map)
        try other.put(obj: map, key: "k", value: .Int(9))
        return map
    }
}
