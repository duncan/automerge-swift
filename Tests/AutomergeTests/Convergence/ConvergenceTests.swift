import Automerge
import Foundation
import Testing

/// Replicas that make random concurrent edits must end up identical, however their changes reach
/// each other: merged in any order, synced, or applied one change at a time in a shuffled order.
///
/// Each seed runs a scenario that is fully determined by the seed, including actors and change
/// timestamps. A failure reports its seed and the edits that led to it; rerun that seed alone to
/// reproduce it.
@Suite("Convergence")
struct ConvergenceTests {
    /// Seeds 1 through 40, or through `AUTOMERGE_CONVERGENCE_SEEDS` if that's set, for a longer run.
    static let seeds: [UInt64] = Array(
        1 ... (ProcessInfo.processInfo.environment["AUTOMERGE_CONVERGENCE_SEEDS"].flatMap(UInt64.init) ?? 40)
    )
    static let replicaCount = 3
    static let rounds = 8

    /// Builds the replicas for `seed`: a shared starting document, then rounds of random edits on
    /// each replica with occasional one-way merges between random pairs.
    static func scenario(seed: UInt64) throws -> (replicas: [Document], editor: RandomEditor) {
        var editor = RandomEditor(seed: seed)
        let base = Document()
        base.actor = actor(0)
        for _ in 0 ..< 3 {
            try editor.edit(base, as: "base")
        }
        commit(base, at: 0)

        let replicas = (1 ... replicaCount).map { index in
            let replica = base.fork()
            replica.actor = actor(UInt8(index))
            return replica
        }
        for round in 1 ... rounds {
            for (index, replica) in replicas.enumerated() {
                for _ in 0 ..< 1 + editor.random.below(4) {
                    try editor.edit(replica, as: "replica \(index)")
                }
                commit(replica, at: round)
            }
            if editor.random.chance(50) {
                let target = editor.random.below(replicaCount)
                let source = (target + 1 + editor.random.below(replicaCount - 1)) % replicaCount
                editor.log.append("round \(round): replica \(target) merges replica \(source)")
                try replicas[target].merge(other: replicas[source])
            }
        }
        return (replicas, editor)
    }

    @Test("Merging in any order converges", arguments: seeds)
    func mergeOrderDoesNotMatter(seed: UInt64) throws {
        let (replicas, editor) = try Self.scenario(seed: seed)
        var results: [Document] = []
        // Each replica merges the others in every order.
        for (index, replica) in replicas.enumerated() {
            let others = replicas.indices.filter { $0 != index }
            for order in [others, others.reversed()] {
                let result = replica.fork()
                for other in order {
                    try result.merge(other: replicas[other])
                }
                results.append(result)
            }
        }
        try expectConverged(results, seed: seed, editor: editor)
    }

    @Test("Merging is idempotent and associative", arguments: seeds.prefix(10))
    func mergeIsIdempotentAndAssociative(seed: UInt64) throws {
        let (replicas, editor) = try Self.scenario(seed: seed)
        let (a, b, c) = (replicas[0], replicas[1], replicas[2])

        // (a + b) + c
        let left = a.fork()
        try left.merge(other: b)
        try left.merge(other: c)
        // a + (b + c)
        let bc = b.fork()
        try bc.merge(other: c)
        let right = a.fork()
        try right.merge(other: bc)
        // Merging the same changes again changes nothing.
        let twice = left.fork()
        try twice.merge(other: b)
        try twice.merge(other: right)

        try expectConverged([left, right, twice], seed: seed, editor: editor)
    }

    @Test("Syncing converges", arguments: seeds)
    func syncConverges(seed: UInt64) throws {
        let (replicas, editor) = try Self.scenario(seed: seed)
        // Sync around a ring, then around it again so every change reaches every replica.
        // SyncState wraps a reference, so each pair's states persist between rounds.
        let states: [[SyncState]] = replicas.map { _ in replicas.map { _ in SyncState() } }
        for _ in 0 ..< 2 {
            for index in replicas.indices {
                let next = (index + 1) % replicas.count
                try sync(replicas[index], states[index][next], replicas[next], states[next][index])
            }
        }
        try expectConverged(replicas, seed: seed, editor: editor)
    }

    @Test("Applying changes one at a time in any order converges", arguments: seeds)
    func shuffledChangesConverge(seed: UInt64) throws {
        let scenario = try Self.scenario(seed: seed)
        let replicas = scenario.replicas
        var editor = scenario.editor
        let merged = replicas[0].fork()
        for replica in replicas.dropFirst() {
            try merged.merge(other: replica)
        }
        let changes = merged.getHistory().compactMap { merged.change(hash: $0)?.bytes }
        #expect(changes.count == merged.getHistory().count)

        // Changes whose dependencies haven't arrived yet are held until they do.
        let shuffled = Document()
        for change in editor.random.shuffle(changes) {
            try shuffled.applyEncodedChanges(encoded: change)
        }
        try expectConverged([merged, shuffled], seed: seed, editor: editor)
    }

    /// Seeds whose replicas end up with different conflicting values for a key, though the same
    /// visible values, because of a merge bug in automerge 0.7.2. See
    /// `KnownAutomergeBugTests.mergeOrderDoesNotChangeConflicts`.
    ///
    /// Running more seeds with `AUTOMERGE_CONVERGENCE_SEEDS` finds more of these: about one seed in ten.
    /// About one in a thousand (seed 513, for one) differs in a visible value too, which
    /// `KnownAutomergeBugTests.mergeOrderDoesNotChangeWinner` reproduces.
    static let seedsWithStaleConflicts: Set<UInt64> = [38]

    /// Checks that every document has the same heads, and so the same changes, and the same contents,
    /// and that each still has those contents after a save and reload. The order `getHistory()` lists
    /// changes in depends on the order they arrived, so it isn't compared.
    ///
    /// Contents are compared twice: first only the values `get` returns, then including every
    /// conflicting value that `getAll` returns.
    private func expectConverged(
        _ docs: [Document],
        seed: UInt64,
        editor: RandomEditor,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let expectedHeads = docs[0].heads()
        let expected = try CorpusDump.contents(of: docs[0])
        var conflictsDiffer = false
        for (index, doc) in docs.enumerated() {
            let heads = doc.heads()
            let contents = try CorpusDump.contents(of: doc)
            let reloaded = try CorpusDump.contents(of: Document(doc.save()))
            let winnersMatch = contents.winners == expected.winners && reloaded.winners == contents.winners
            guard heads == expectedHeads, winnersMatch else {
                try record(
                    "document \(index) differs from document 0 (heads equal: \(heads == expectedHeads))",
                    expected: expected, actual: contents, seed: seed, editor: editor,
                    sourceLocation: sourceLocation
                )
                return
            }
            if contents != expected || reloaded != contents {
                conflictsDiffer = true
            }
        }
        guard conflictsDiffer else { return }
        if Self.seedsWithStaleConflicts.contains(seed) {
            withKnownIssue("automerge 0.7.2 can keep overwritten values in a key's conflicts after a merge") {
                Issue.record("conflicting values differ between documents or after reloading")
            }
        } else {
            try record(
                "conflicting values differ between documents or after reloading",
                expected: expected, actual: nil, seed: seed, editor: editor, sourceLocation: sourceLocation
            )
        }
    }

    private func record(
        _ problem: String,
        expected: JSONValue,
        actual: JSONValue?,
        seed: UInt64,
        editor: RandomEditor,
        sourceLocation: SourceLocation
    ) throws {
        var message = "Seed \(seed): \(problem).\nExpected:\n\(try expected.rendered)\n"
        if let actual {
            message += "Actual:\n\(try actual.rendered)\n"
        }
        message += "Edits:\n\(editor.log.joined(separator: "\n"))"
        Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
    }
}

extension JSONValue {
    /// This dump with every conflict replaced by its winning value: what `get` returns.
    var winners: JSONValue {
        switch self {
        case let .object(members):
            if case let .object(conflict)? = members["conflict"], let winner = conflict["winner"] {
                return winner.winners
            }
            return .object(members.mapValues(\.winners))
        case let .array(values):
            return .array(values.map(\.winners))
        default:
            return self
        }
    }
}

private func actor(_ index: UInt8) -> ActorId {
    ActorId(data: Data(repeating: index, count: 16))!
}

private func commit(_ doc: Document, at round: Int) {
    doc.commitWith(message: nil, timestamp: Date(timeIntervalSince1970: 1_704_067_200 + TimeInterval(round)))
}

/// Exchanges sync messages between two documents until neither has anything more to send.
private func sync(_ left: Document, _ leftState: SyncState, _ right: Document, _ rightState: SyncState) throws {
    for _ in 0 ..< 100 {
        var quiet = true
        if let message = left.generateSyncMessage(state: leftState) {
            quiet = false
            try right.receiveSyncMessage(state: rightState, message: message)
        }
        if let message = right.generateSyncMessage(state: rightState) {
            quiet = false
            try left.receiveSyncMessage(state: leftState, message: message)
        }
        if quiet { return }
    }
    Issue.record("documents did not finish syncing within 100 rounds")
}
