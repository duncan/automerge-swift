import Automerge
import Foundation
import Testing

/// Minimal reproductions of bugs the convergence tests found in the automerge crate this package uses
/// (0.7.2). Each is fixed in automerge 0.12.0. When the crate is updated, these known issues stop
/// being recorded, which fails the test so that the marker can be removed.
@Suite("Known automerge 0.7.2 bugs")
struct KnownAutomergeBugTests {
    @Test(
        "Encoding a change that increments a counter in a list and then inserts into the list",
        .disabled("automerge 0.7.2 panics in the change collector, which crashes the test process")
    )
    func incrementedListCounterEncodes() throws {
        let doc = Document()
        let list = try doc.putObject(obj: .ROOT, key: "list", ty: .List)
        try doc.insert(obj: list, index: 0, value: .Counter(1))
        try doc.increment(obj: list, index: 0, by: 1)
        try doc.insert(obj: list, index: 1, value: .Null)
        doc.commitWith(message: nil, timestamp: Date(timeIntervalSince1970: 0))

        // Both of these rebuild the change's bytes; the second is what syncing does.
        let changes = doc.getHistory().compactMap { doc.change(hash: $0) }
        #expect(changes.count == 2)
        #expect(doc.generateSyncMessage(state: SyncState()) != nil)
    }

    @Test("Merge order doesn't change a key's conflicting values")
    func mergeOrderDoesNotChangeConflicts() throws {
        let base = Document()
        base.actor = actor(0)
        try base.put(obj: .ROOT, key: "a", value: .Null)
        let (r0, r1, r2) = (base.fork(), base.fork(), base.fork())
        r0.actor = actor(1)
        r1.actor = actor(2)
        r2.actor = actor(3)

        try r0.put(obj: .ROOT, key: "a", value: .Uint(7))
        try r2.put(obj: .ROOT, key: "a", value: .Counter(0))
        try r0.merge(other: r2)
        try r1.delete(obj: .ROOT, key: "a")
        try r0.increment(obj: .ROOT, key: "a", by: 1)

        let forward = r0.fork()
        try forward.merge(other: r1)
        try forward.merge(other: r2)
        let backward = r2.fork()
        try backward.merge(other: r1)
        try backward.merge(other: r0)
        let reloaded = try Document(backward.save())

        #expect(try backward.get(obj: .ROOT, key: "a") == forward.get(obj: .ROOT, key: "a"))
        let backwardValues = try backward.getAll(obj: .ROOT, key: "a")
        let forwardValues = try forward.getAll(obj: .ROOT, key: "a")
        let reloadedValues = try reloaded.getAll(obj: .ROOT, key: "a")
        withKnownIssue("automerge 0.7.2 keeps the overwritten Uint(7) in memory after merging backward") {
            #expect(backwardValues == forwardValues)
            #expect(backwardValues == reloadedValues)
        }
    }

    @Test("Merge order doesn't change a key's visible value")
    func mergeOrderDoesNotChangeWinner() throws {
        let base = Document()
        base.actor = actor(0)
        try base.put(obj: .ROOT, key: "x", value: .Int(0))
        let (r0, r1, r2) = (base.fork(), base.fork(), base.fork())
        r0.actor = actor(1)
        r1.actor = actor(2)
        r2.actor = actor(3)

        try r1.put(obj: .ROOT, key: "d", value: .Counter(0))
        try r0.put(obj: .ROOT, key: "d", value: .Counter(7))
        _ = try r0.putObject(obj: .ROOT, key: "d", ty: .Map)
        try r2.put(obj: .ROOT, key: "d", value: .Counter(0))
        try r0.merge(other: r2)
        try r2.delete(obj: .ROOT, key: "d")
        try r1.merge(other: r0)
        try r1.increment(obj: .ROOT, key: "d", by: 3)

        let forward = r0.fork()
        try forward.merge(other: r1)
        try forward.merge(other: r2)
        let backward = r2.fork()
        try backward.merge(other: r1)
        try backward.merge(other: r0)

        let forwardValue = try forward.get(obj: .ROOT, key: "d")
        let reloadedValue = try Document(backward.save()).get(obj: .ROOT, key: "d")
        let backwardValue = try backward.get(obj: .ROOT, key: "d")
        #expect(forwardValue == .Scalar(.Counter(3)))
        #expect(reloadedValue == .Scalar(.Counter(3)))
        withKnownIssue("automerge 0.7.2 returns the overwritten map after merging backward, until reloaded") {
            #expect(backwardValue == forwardValue)
        }
    }

    @Test("Merging into a document that made a splice that changes nothing", arguments: [ObjType.List, .Text])
    func mergeAfterEmptySplice(type: ObjType) throws {
        let base = Document()
        base.actor = actor(0)
        let obj = try base.putObject(obj: .ROOT, key: "obj", ty: type)
        let (r0, r1) = (base.fork(), base.fork())
        r0.actor = actor(1)
        r1.actor = actor(2)

        if type == .Text {
            try r0.spliceText(obj: obj, start: 0, delete: 0, value: "")
            try r1.spliceText(obj: obj, start: 0, delete: 0, value: "x")
        } else {
            try r0.splice(obj: obj, start: 0, delete: 0, values: [])
            try r1.insert(obj: obj, index: 0, value: .Null)
        }
        withKnownIssue("automerge 0.7.2 panics with PatchLogMismatch, which surfaces as an internal error") {
            try r0.merge(other: r1)
            #expect(r0.length(obj: obj) == 1)
        }
    }
}

private func actor(_ byte: UInt8) -> ActorId {
    ActorId(data: Data(repeating: byte, count: 16))!
}
