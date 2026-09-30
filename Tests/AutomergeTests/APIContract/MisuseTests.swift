import Automerge
import Foundation
import Testing

/// Calls that don't make sense for the object they're given must throw, and change nothing.
@Suite("Misusing objects")
struct MisuseTests {
    static let wrongObjectType: [NamedOperation] = [
        NamedOperation("insert into a map") { f in try f.doc.insert(obj: .ROOT, index: 0, value: .Int(1)) },
        NamedOperation("insertObject into a map") { f in _ = try f.doc.insertObject(obj: .ROOT, index: 0, ty: .Map) },
        NamedOperation("put by index in a map") { f in try f.doc.put(obj: .ROOT, index: 0, value: .Int(1)) },
        NamedOperation("splice a map") { f in try f.doc.splice(obj: .ROOT, start: 0, delete: 0, values: [.Int(1)]) },
        NamedOperation("spliceText a map") { f in try f.doc.spliceText(obj: .ROOT, start: 0, delete: 0, value: "x") },
        NamedOperation("updateText a map") { f in try f.doc.updateText(obj: .ROOT, value: "x") },
        NamedOperation("mark a map") { f in
            try f.doc.mark(obj: .ROOT, start: 0, end: 1, expand: .none, name: "bold", value: .Boolean(true))
        },
        NamedOperation("text of a map") { f in _ = try f.doc.text(obj: .ROOT) },
        NamedOperation("marks of a map") { f in _ = try f.doc.marks(obj: .ROOT) },
        NamedOperation("put by key in a list") { f in try f.doc.put(obj: f.list, key: "a", value: .Int(1)) },
        NamedOperation("putObject by key in a list") { f in _ = try f.doc.putObject(obj: f.list, key: "a", ty: .Map) },
        NamedOperation("get by key from a list") { f in _ = try f.doc.get(obj: f.list, key: "a") },
        NamedOperation("mapEntries of a list") { f in _ = try f.doc.mapEntries(obj: f.list) },
        NamedOperation("spliceText a list") { f in try f.doc.spliceText(obj: f.list, start: 0, delete: 0, value: "x") },
        NamedOperation("updateText a list") { f in try f.doc.updateText(obj: f.list, value: "x") },
        NamedOperation("text of a list") { f in _ = try f.doc.text(obj: f.list) },
        NamedOperation("mark a list") { f in
            try f.doc.mark(obj: f.list, start: 0, end: 1, expand: .none, name: "bold", value: .Boolean(true))
        },
        NamedOperation("put by key in text") { f in try f.doc.put(obj: f.text, key: "a", value: .Int(1)) },
        NamedOperation("insert a value into text") { f in try f.doc.insert(obj: f.text, index: 0, value: .Int(1)) },
        NamedOperation("splice values into text") { f in
            try f.doc.splice(obj: f.text, start: 0, delete: 0, values: [.Int(1)])
        },
        NamedOperation("putObject by index in text") { f in _ = try f.doc.putObject(obj: f.text, index: 0, ty: .Map) },
    ]

    @Test("Operations on the wrong type of object throw WrongObjectType", arguments: wrongObjectType)
    func wrongObjectTypeThrows(operation: NamedOperation) throws {
        let fixture = try ContractFixture()
        try fixture.expectRejected(\.isWrongObjectType, operation.run)
    }

    static let invalidIncrements: [NamedOperation] = [
        NamedOperation("increment a string") { f in try f.doc.increment(obj: .ROOT, key: "string", by: 1) },
        NamedOperation("increment a missing key") { f in try f.doc.increment(obj: .ROOT, key: "missing", by: 1) },
        NamedOperation("increment a list element that isn't a counter") { f in
            try f.doc.increment(obj: f.list, index: 0, by: 1)
        },
    ]

    @Test("Incrementing something that isn't a counter throws", arguments: invalidIncrements)
    func invalidIncrementThrows(operation: NamedOperation) throws {
        let fixture = try ContractFixture()
        try fixture.expectRejected({ $0.isInternal(containing: "against a counter") }, operation.run)
    }

    @Test("A cursor into a map throws")
    func cursorIntoMapThrows() throws {
        let fixture = try ContractFixture()
        try fixture.expectRejected({ $0.isInternal(containing: "invalid op for object of type `map`") }) { f in
            _ = try f.doc.cursor(obj: .ROOT, position: 0)
        }
    }

    @Test("Deleting a missing key does nothing")
    func deletingMissingKey() throws {
        let fixture = try ContractFixture()
        let before = try CorpusDump.contents(of: fixture.doc)
        try fixture.doc.delete(obj: .ROOT, key: "missing")
        #expect(try CorpusDump.contents(of: fixture.doc) == before)
    }

    @Test("values returns a map's values and text's characters")
    func valuesOfMapAndText() throws {
        let fixture = try ContractFixture()
        let mapValues = try fixture.doc.values(obj: fixture.map)
        #expect(mapValues == [.Scalar(.Int(1))])
        let characters = try fixture.doc.values(obj: fixture.text)
        #expect(characters == ["h", "e", "l", "l", "o"].map { .Scalar(.String($0)) })
    }
}

/// Indices past the end of an object. Writes must throw and change nothing; reads find nothing.
@Suite("Indices past the end")
struct PastEndTests {
    static let writes: [NamedOperation] = [
        NamedOperation("insert into a list") { f in try f.doc.insert(obj: f.list, index: 4, value: .Int(1)) },
        NamedOperation("insertObject into a list") { f in _ = try f.doc.insertObject(obj: f.list, index: 4, ty: .Map) },
        NamedOperation("put in a list") { f in try f.doc.put(obj: f.list, index: 3, value: .Int(1)) },
        NamedOperation("putObject in a list") { f in _ = try f.doc.putObject(obj: f.list, index: 3, ty: .Map) },
        NamedOperation("delete from a list") { f in try f.doc.delete(obj: f.list, index: 3) },
        NamedOperation("increment in a list") { f in try f.doc.increment(obj: f.list, index: 3, by: 1) },
        NamedOperation("splice a list") { f in try f.doc.splice(obj: f.list, start: 4, delete: 0, values: [.Int(1)]) },
        NamedOperation("splice a list backwards past its start") { f in
            try f.doc.splice(obj: f.list, start: 1, delete: -2, values: [])
        },
        NamedOperation("splice text") { f in try f.doc.spliceText(obj: f.text, start: 6, delete: 0, value: "x") },
        NamedOperation("splice text backwards past its start") { f in
            try f.doc.spliceText(obj: f.text, start: 3, delete: -4)
        },
        NamedOperation("mark text starting past its end") { f in
            try f.doc.mark(obj: f.text, start: 6, end: 7, expand: .none, name: "bold", value: .Boolean(true))
        },
        NamedOperation("mark text ending past its end") { f in
            try f.doc.mark(obj: f.text, start: 0, end: 6, expand: .none, name: "bold", value: .Boolean(true))
        },
    ]

    @Test("Writes past the end throw", arguments: writes)
    func writesPastEndThrow(operation: NamedOperation) throws {
        let fixture = try ContractFixture()
        try fixture.expectRejected(\.isOutOfBounds, operation.run)
    }

    @Test("Inserting at the end appends")
    func insertAtEnd() throws {
        let fixture = try ContractFixture()
        try fixture.doc.insert(obj: fixture.list, index: 3, value: .String("d"))
        try fixture.doc.spliceText(obj: fixture.text, start: 5, delete: 0, value: "!")
        let values = try fixture.doc.values(obj: fixture.list)
        #expect(values == ["a", "b", "c", "d"].map { .Scalar(.String($0)) })
        #expect(try fixture.doc.text(obj: fixture.text) == "hello!")
    }

    @Test("Reads past the end find nothing")
    func readsPastEnd() throws {
        let fixture = try ContractFixture()
        let heads = fixture.doc.heads()
        #expect(try fixture.doc.get(obj: fixture.list, index: 3) == nil)
        #expect(try fixture.doc.getAll(obj: fixture.list, index: 3).isEmpty)
        #expect(try fixture.doc.getAt(obj: fixture.list, index: 3, heads: heads) == nil)
        #expect(try fixture.doc.marksAt(obj: fixture.text, position: .index(10)).isEmpty)
    }

    @Test("Deleting past the end deletes to the end")
    func deleteClampsToEnd() throws {
        let fixture = try ContractFixture()
        try fixture.doc.splice(obj: fixture.list, start: 1, delete: 10, values: [])
        try fixture.doc.spliceText(obj: fixture.text, start: 2, delete: 100)
        let values = try fixture.doc.values(obj: fixture.list)
        #expect(values == [.Scalar(.String("a"))])
        #expect(try fixture.doc.text(obj: fixture.text) == "he")
    }

    @Test("A negative delete count deletes backwards from the start index")
    func negativeDeleteDeletesBackwards() throws {
        let fixture = try ContractFixture()
        try fixture.doc.splice(obj: fixture.list, start: 2, delete: -1, values: [])
        try fixture.doc.spliceText(obj: fixture.text, start: 3, delete: -2)
        let values = try fixture.doc.values(obj: fixture.list)
        #expect(values == [.Scalar(.String("a")), .Scalar(.String("c"))])
        #expect(try fixture.doc.text(obj: fixture.text) == "hlo")
    }

    @Test("A cursor past the end is at the end")
    func cursorPastEnd() throws {
        let fixture = try ContractFixture()
        let cursor = try fixture.doc.cursor(obj: fixture.text, position: 10)
        #expect(try fixture.doc.position(obj: fixture.text, cursor: cursor) == 5)
    }

    @Test("A mark with an empty or reversed range does nothing", arguments: [(UInt64(2), UInt64(2)), (3, 1)])
    func emptyOrReversedMarkDoesNothing(start: UInt64, end: UInt64) throws {
        let fixture = try ContractFixture()
        try fixture.doc.mark(obj: fixture.text, start: start, end: end, expand: .none, name: "bold", value: .Boolean(true))
        let marks = try fixture.doc.marks(obj: fixture.text)
        #expect(marks.isEmpty)
    }
}
