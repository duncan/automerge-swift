import Automerge
import Foundation
import Testing

/// How concurrent changes resolve when replicas merge. Each test makes the same kind of concurrent
/// change on two replicas, merges them in both directions, and checks that both directions agree on
/// the expected result.
@Suite("Merge semantics")
struct MergeSemanticsTests {
    /// A document with a list at `list` and text at `text`, and two forks of it with fixed actors, so
    /// that which actor wins a conflict is deterministic. Actor `b` sorts after actor `a`.
    struct Replicas {
        let a: Document
        let b: Document
        let list: ObjId
        let text: ObjId

        init(setUp: (Document, ObjId, ObjId) throws -> Void = { _, _, _ in }) throws {
            let base = Document()
            base.actor = actor(0x00)
            list = try base.putObject(obj: .ROOT, key: "list", ty: .List)
            text = try base.putObject(obj: .ROOT, key: "text", ty: .Text)
            try setUp(base, list, text)
            a = base.fork()
            a.actor = actor(0x0A)
            b = base.fork()
            b.actor = actor(0x0B)
        }

        /// Merges the replicas in both directions, checks that the results agree, and returns one.
        func merged(sourceLocation: SourceLocation = #_sourceLocation) throws -> Document {
            let ab = a.fork()
            try ab.merge(other: b)
            let ba = b.fork()
            try ba.merge(other: a)
            #expect(ab.heads() == ba.heads(), sourceLocation: sourceLocation)
            #expect(
                try CorpusDump.contents(of: ab) == CorpusDump.contents(of: ba),
                "merging in either direction should give the same document",
                sourceLocation: sourceLocation
            )
            return ab
        }
    }

    // MARK: Maps

    @Test("Concurrent puts to one key conflict, and the higher actor wins")
    func concurrentPutsConflict() throws {
        let replicas = try Replicas()
        try replicas.a.put(obj: .ROOT, key: "key", value: .String("from a"))
        try replicas.b.put(obj: .ROOT, key: "key", value: .Int(2))

        let doc = try replicas.merged()
        #expect(try doc.get(obj: .ROOT, key: "key") == .Scalar(.Int(2)))
        #expect(try doc.getAll(obj: .ROOT, key: "key") == [.Scalar(.String("from a")), .Scalar(.Int(2))])
    }

    @Test("A later put resolves a conflict")
    func laterPutResolvesConflict() throws {
        let replicas = try Replicas()
        try replicas.a.put(obj: .ROOT, key: "key", value: .String("from a"))
        try replicas.b.put(obj: .ROOT, key: "key", value: .String("from b"))
        let doc = try replicas.merged()

        try doc.put(obj: .ROOT, key: "key", value: .String("resolved"))
        #expect(try doc.getAll(obj: .ROOT, key: "key") == [.Scalar(.String("resolved"))])
    }

    @Test("A put concurrent with a delete survives")
    func putSurvivesConcurrentDelete() throws {
        let replicas = try Replicas { base, _, _ in
            try base.put(obj: .ROOT, key: "key", value: .String("original"))
        }
        try replicas.a.delete(obj: .ROOT, key: "key")
        try replicas.b.put(obj: .ROOT, key: "key", value: .String("updated"))

        let doc = try replicas.merged()
        #expect(try doc.getAll(obj: .ROOT, key: "key") == [.Scalar(.String("updated"))])
    }

    @Test("Concurrent deletes of one key delete it once")
    func concurrentDeletes() throws {
        let replicas = try Replicas { base, _, _ in
            try base.put(obj: .ROOT, key: "key", value: .String("original"))
            try base.put(obj: .ROOT, key: "other", value: .String("kept"))
        }
        try replicas.a.delete(obj: .ROOT, key: "key")
        try replicas.b.delete(obj: .ROOT, key: "key")

        let doc = try replicas.merged()
        #expect(try doc.get(obj: .ROOT, key: "key") == nil)
        #expect(doc.keys(obj: .ROOT) == ["list", "other", "text"])
    }

    @Test("Edits inside a map concurrent with deleting it are lost")
    func editsInsideDeletedMapAreLost() throws {
        var map = ObjId.ROOT
        let replicas = try Replicas { base, _, _ in
            map = try base.putObject(obj: .ROOT, key: "map", ty: .Map)
            try base.put(obj: map, key: "value", value: .Int(1))
        }
        try replicas.a.delete(obj: .ROOT, key: "map")
        try replicas.b.put(obj: map, key: "value", value: .Int(2))
        try replicas.b.put(obj: map, key: "added", value: .Int(3))

        let doc = try replicas.merged()
        #expect(try doc.get(obj: .ROOT, key: "map") == nil)
    }

    @Test("Concurrently created objects at one key conflict, and each keeps its own contents")
    func concurrentObjectsConflict() throws {
        let replicas = try Replicas()
        let mapA = try replicas.a.putObject(obj: .ROOT, key: "key", ty: .Map)
        try replicas.a.put(obj: mapA, key: "from", value: .String("a"))
        let mapB = try replicas.b.putObject(obj: .ROOT, key: "key", ty: .Map)
        try replicas.b.put(obj: mapB, key: "from", value: .String("b"))

        let doc = try replicas.merged()
        #expect(try doc.get(obj: .ROOT, key: "key") == .Object(mapB, .Map))
        #expect(try doc.getAll(obj: .ROOT, key: "key") == [.Object(mapA, .Map), .Object(mapB, .Map)])
        #expect(try doc.get(obj: mapA, key: "from") == .Scalar(.String("a")))
        #expect(try doc.get(obj: mapB, key: "from") == .Scalar(.String("b")))
    }

    // MARK: Counters

    @Test("Concurrent increments add up")
    func concurrentIncrementsAddUp() throws {
        let replicas = try Replicas { base, _, _ in
            try base.put(obj: .ROOT, key: "count", value: .Counter(10))
        }
        try replicas.a.increment(obj: .ROOT, key: "count", by: 3)
        try replicas.a.increment(obj: .ROOT, key: "count", by: 2)
        try replicas.b.increment(obj: .ROOT, key: "count", by: -4)

        let doc = try replicas.merged()
        #expect(try doc.get(obj: .ROOT, key: "count") == .Scalar(.Counter(11)))
    }

    @Test("Setting a counter overwrites concurrent increments")
    func putOverwritesConcurrentIncrement() throws {
        let replicas = try Replicas { base, _, _ in
            try base.put(obj: .ROOT, key: "count", value: .Counter(10))
        }
        try replicas.a.increment(obj: .ROOT, key: "count", by: 5)
        try replicas.b.put(obj: .ROOT, key: "count", value: .Counter(0))

        let doc = try replicas.merged()
        // An increment isn't a new value, so it doesn't conflict with the put: it applies to the
        // counter the put replaced.
        let values = try doc.getAll(obj: .ROOT, key: "count")
        #expect(values == [.Scalar(.Counter(0))])
    }

    // MARK: Lists

    @Test("Concurrent inserts at one index both survive, in the same order on both replicas")
    func concurrentInsertsAtOneIndex() throws {
        let replicas = try Replicas { base, list, _ in
            try base.insert(obj: list, index: 0, value: .String("first"))
            try base.insert(obj: list, index: 1, value: .String("last"))
        }
        try replicas.a.insert(obj: replicas.list, index: 1, value: .String("a"))
        try replicas.b.insert(obj: replicas.list, index: 1, value: .String("b"))

        let doc = try replicas.merged()
        #expect(try doc.values(obj: replicas.list) == ["first", "b", "a", "last"].map { .Scalar(.String($0)) })
    }

    @Test("Concurrent deletes of one list element delete only that element")
    func concurrentListDeletes() throws {
        let replicas = try Replicas { base, list, _ in
            for (index, value) in ["x", "y", "z"].enumerated() {
                try base.insert(obj: list, index: UInt64(index), value: .String(value))
            }
        }
        try replicas.a.delete(obj: replicas.list, index: 1)
        try replicas.b.delete(obj: replicas.list, index: 1)

        let doc = try replicas.merged()
        #expect(try doc.values(obj: replicas.list) == [.Scalar(.String("x")), .Scalar(.String("z"))])
    }

    @Test("Setting a list element concurrently with deleting it keeps the element")
    func putSurvivesConcurrentListDelete() throws {
        let replicas = try Replicas { base, list, _ in
            try base.insert(obj: list, index: 0, value: .String("original"))
        }
        try replicas.a.delete(obj: replicas.list, index: 0)
        try replicas.b.put(obj: replicas.list, index: 0, value: .String("updated"))

        let doc = try replicas.merged()
        #expect(try doc.values(obj: replicas.list) == [.Scalar(.String("updated"))])
    }

    @Test("Inserts next to a concurrently deleted element keep their place")
    func insertNextToDeletedElement() throws {
        let replicas = try Replicas { base, list, _ in
            for (index, value) in ["x", "y", "z"].enumerated() {
                try base.insert(obj: list, index: UInt64(index), value: .String(value))
            }
        }
        try replicas.a.delete(obj: replicas.list, index: 1)
        try replicas.b.insert(obj: replicas.list, index: 2, value: .String("after y"))

        let doc = try replicas.merged()
        #expect(try doc.values(obj: replicas.list) == ["x", "after y", "z"].map { .Scalar(.String($0)) })
    }

    // MARK: Text

    @Test("Words typed concurrently at one position don't interleave")
    func concurrentTypingDoesNotInterleave() throws {
        let replicas = try Replicas { base, _, text in
            try base.spliceText(obj: text, start: 0, delete: 0, value: "[]")
        }
        // Each replica types its word one character at a time, as an editor would.
        for (doc, word) in [(replicas.a, "alpha"), (replicas.b, "beta")] {
            for (offset, character) in word.enumerated() {
                try doc.spliceText(obj: replicas.text, start: UInt64(1 + offset), delete: 0, value: String(character))
            }
        }

        let doc = try replicas.merged()
        let merged = try doc.text(obj: replicas.text)
        #expect(merged == "[betaalpha]" || merged == "[alphabeta]")
    }

    @Test("Overlapping concurrent deletes remove each character once")
    func overlappingTextDeletes() throws {
        let replicas = try Replicas { base, _, text in
            try base.spliceText(obj: text, start: 0, delete: 0, value: "0123456789")
        }
        try replicas.a.spliceText(obj: replicas.text, start: 2, delete: 4) // removes 2345
        try replicas.b.spliceText(obj: replicas.text, start: 4, delete: 4) // removes 4567

        let doc = try replicas.merged()
        #expect(try doc.text(obj: replicas.text) == "0189")
    }

    @Test("Text inserted inside a concurrently deleted range survives")
    func insertInsideDeletedRange() throws {
        let replicas = try Replicas { base, _, text in
            try base.spliceText(obj: text, start: 0, delete: 0, value: "keep [remove] keep")
        }
        try replicas.a.spliceText(obj: replicas.text, start: 5, delete: 8)
        try replicas.b.spliceText(obj: replicas.text, start: 8, delete: 0, value: "NEW")

        let doc = try replicas.merged()
        #expect(try doc.text(obj: replicas.text) == "keep NEW keep")
    }

    @Test("Concurrent marks on overlapping ranges both apply")
    func concurrentMarks() throws {
        let replicas = try Replicas { base, _, text in
            try base.spliceText(obj: text, start: 0, delete: 0, value: "0123456789")
        }
        try replicas.a.mark(obj: replicas.text, start: 0, end: 6, expand: .none, name: "bold", value: .Boolean(true))
        try replicas.b.mark(obj: replicas.text, start: 4, end: 10, expand: .none, name: "italic", value: .Boolean(true))

        let doc = try replicas.merged()
        #expect(try doc.marks(obj: replicas.text) == [
            Mark(start: 0, end: 6, name: "bold", value: .Boolean(true)),
            Mark(start: 4, end: 10, name: "italic", value: .Boolean(true)),
        ])
    }

    @Test("Concurrently setting and clearing one mark on overlapping ranges resolves the same everywhere")
    func concurrentMarkAndUnmark() throws {
        let replicas = try Replicas { base, _, text in
            try base.spliceText(obj: text, start: 0, delete: 0, value: "0123456789")
            try base.mark(obj: text, start: 0, end: 10, expand: .none, name: "bold", value: .Boolean(true))
        }
        try replicas.a.mark(obj: replicas.text, start: 2, end: 5, expand: .none, name: "bold", value: .Null)
        try replicas.b.mark(obj: replicas.text, start: 4, end: 8, expand: .none, name: "bold", value: .String("heavy"))

        let doc = try replicas.merged()
        // Where the ranges overlap (4..<5) the later op wins, which is b's, since actor b sorts after a.
        #expect(try doc.marks(obj: replicas.text) == [
            Mark(start: 0, end: 2, name: "bold", value: .Boolean(true)),
            Mark(start: 4, end: 8, name: "bold", value: .String("heavy")),
            Mark(start: 8, end: 10, name: "bold", value: .Boolean(true)),
        ])
    }

    @Test("A cursor follows its character through concurrent edits")
    func cursorFollowsConcurrentEdits() throws {
        let replicas = try Replicas { base, _, text in
            try base.spliceText(obj: text, start: 0, delete: 0, value: "hello world")
        }
        let cursor = try replicas.a.cursor(obj: replicas.text, position: 6) // "w"
        try replicas.a.spliceText(obj: replicas.text, start: 0, delete: 0, value: ">> ")
        try replicas.b.spliceText(obj: replicas.text, start: 5, delete: 0, value: ",")
        try replicas.b.spliceText(obj: replicas.text, start: 12, delete: 0, value: "!")

        let doc = try replicas.merged()
        let text = try doc.text(obj: replicas.text)
        let position = try doc.position(obj: replicas.text, cursor: cursor)
        #expect(text == ">> hello, world!")
        #expect(position == 10)
    }
}

private func actor(_ byte: UInt8) -> ActorId {
    ActorId(data: Data(repeating: byte, count: 16))!
}
