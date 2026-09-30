import Automerge
import Foundation

/// SplitMix64: a small, fast generator whose sequence depends only on its seed, so a failing seed
/// reproduces exactly on any platform. The bounded helpers below avoid the standard library's
/// `random(in:using:)`, whose algorithm isn't guaranteed to stay the same between Swift versions.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `0 ..< count`. The modulo bias is irrelevant for counts this small.
    mutating func below(_ count: Int) -> Int {
        precondition(count > 0)
        return Int(next() % UInt64(count))
    }

    /// True `percent` percent of the time.
    mutating func chance(_ percent: Int) -> Bool {
        below(100) < percent
    }

    mutating func pick<T>(_ values: [T]) -> T {
        values[below(values.count)]
    }

    mutating func shuffle<T>(_ values: [T]) -> [T] {
        var values = values
        guard values.count > 1 else { return values }
        for index in stride(from: values.count - 1, to: 0, by: -1) {
            values.swapAt(index, below(index + 1))
        }
        return values
    }
}

/// Makes random, valid edits to documents: puts, inserts, deletes, increments, splices and marks,
/// on maps, lists and text anywhere in the document. Keys are drawn from a small pool so that
/// replicas editing concurrently often touch the same keys and elements.
struct RandomEditor {
    var random: SeededGenerator
    /// A description of every edit made so far, for reproducing a failure.
    var log: [String] = []

    /// Objects beyond this many aren't created, which keeps documents small enough to check quickly.
    let maxObjects = 12

    init(seed: UInt64) {
        random = SeededGenerator(seed: seed)
    }

    static let keys = ["a", "b", "c", "d", "e"]
    static let strings = ["", "x", "hello", "🇬🇧", "👨‍👨‍👧‍👦", "e\u{301}", "line\nbreak"]
    static let markNames = ["bold", "link", "comment"]

    mutating func edit(_ doc: Document, as name: String) throws {
        let objects = try Self.objects(in: doc)
        let (obj, type) = random.pick(objects)
        let canCreate = objects.count < maxObjects
        switch type {
        case .Map: try editMap(obj, in: doc, as: name, canCreate: canCreate)
        case .List: try editList(obj, in: doc, as: name, canCreate: canCreate)
        case .Text: try editText(obj, in: doc, as: name)
        }
    }

    private mutating func editMap(_ obj: ObjId, in doc: Document, as name: String, canCreate: Bool) throws {
        let key = random.pick(Self.keys)
        let existing = try doc.get(obj: obj, key: key)
        switch random.below(10) {
        case 0 ..< 4:
            let value = randomScalar()
            log.append("\(name): put \(obj)[\(key)] = \(value)")
            try doc.put(obj: obj, key: key, value: value)
        case 4 ..< 6 where canCreate:
            let type = randomObjectType()
            log.append("\(name): putObject \(obj)[\(key)] = \(type)")
            _ = try doc.putObject(obj: obj, key: key, ty: type)
        case 6 ..< 8 where existing != nil:
            log.append("\(name): delete \(obj)[\(key)]")
            try doc.delete(obj: obj, key: key)
        default:
            if case .Scalar(.Counter) = existing {
                let amount = Int64(random.below(21)) - 10
                log.append("\(name): increment \(obj)[\(key)] by \(amount)")
                try doc.increment(obj: obj, key: key, by: amount)
            } else {
                log.append("\(name): put \(obj)[\(key)] = counter 0")
                try doc.put(obj: obj, key: key, value: .Counter(0))
            }
        }
    }

    private mutating func editList(_ obj: ObjId, in doc: Document, as name: String, canCreate: Bool) throws {
        let length = Int(doc.length(obj: obj))
        let index = UInt64(random.below(length + 1))
        switch random.below(10) {
        case 0 ..< 3:
            let value = randomScalar()
            log.append("\(name): insert \(obj)[\(index)] = \(value)")
            try doc.insert(obj: obj, index: index, value: value)
        case 3 ..< 5 where canCreate:
            let type = randomObjectType()
            log.append("\(name): insertObject \(obj)[\(index)] = \(type)")
            _ = try doc.insertObject(obj: obj, index: index, ty: type)
        case 5 ..< 7 where length > 0:
            let index = UInt64(random.below(length))
            let value = randomScalar()
            log.append("\(name): put \(obj)[\(index)] = \(value)")
            try doc.put(obj: obj, index: index, value: value)
        case 7 where length > 0:
            let index = UInt64(random.below(length))
            log.append("\(name): delete \(obj)[\(index)]")
            try doc.delete(obj: obj, index: index)
        case 8 where length > 0:
            // Counters in lists are never incremented: automerge 0.7.2 panics when it encodes a change
            // that increments a counter in a list and inserts after it. See
            // `KnownAutomergeBugTests.incrementedListCounterEncodes`.
            let index = UInt64(random.below(length))
            log.append("\(name): put \(obj)[\(index)] = counter 1")
            try doc.put(obj: obj, index: index, value: .Counter(1))
        default:
            let delete = random.below(min(3, length - Int(index)) + 1)
            // A splice always inserts something: automerge 0.7.2 fails to merge into a document that
            // made a splice that changes nothing. See `KnownAutomergeBugTests.mergeAfterEmptySplice`.
            let values = (0 ..< 1 + random.below(2)).map { _ in randomScalar() }
            log.append("\(name): splice \(obj)[\(index)] delete \(delete) insert \(values)")
            try doc.splice(obj: obj, start: index, delete: Int64(delete), values: values)
        }
    }

    private mutating func editText(_ obj: ObjId, in doc: Document, as name: String) throws {
        let length = Int(doc.length(obj: obj))
        switch random.below(10) {
        case 0 ..< 5:
            let start = random.below(length + 1)
            let delete = random.below(min(3, length - start) + 1)
            var value = random.pick(Self.strings)
            if delete == 0, value.isEmpty {
                // See the list splice above: automerge 0.7.2 can't merge after a splice that changes nothing.
                value = "x"
            }
            log.append("\(name): spliceText \(obj)[\(start)] delete \(delete) insert \(value.debugDescription)")
            try doc.spliceText(obj: obj, start: UInt64(start), delete: Int64(delete), value: value)
        case 5 ..< 8 where length > 0:
            let start = random.below(length)
            let end = start + 1 + random.below(length - start)
            let markName = random.pick(Self.markNames)
            let expand = random.pick([ExpandMark.none, .before, .after, .both])
            let value: ScalarValue = random.chance(20) ? .Null : random.pick([.Boolean(true), .String("v")])
            log.append("\(name): mark \(obj)[\(start)..<\(end)] \(markName) = \(value) expand \(expand)")
            try doc.mark(
                obj: obj,
                start: UInt64(start),
                end: UInt64(end),
                expand: expand,
                name: markName,
                value: value
            )
        default:
            let value = random.pick(Self.strings) + random.pick(Self.strings)
            log.append("\(name): updateText \(obj) = \(value.debugDescription)")
            try doc.updateText(obj: obj, value: value)
        }
    }

    private mutating func randomScalar() -> ScalarValue {
        switch random.below(10) {
        case 0: return .String(random.pick(Self.strings))
        case 1: return .Int(random.pick([0, -1, 42, .min, .max]))
        case 2: return .Uint(random.pick([0, 7, .max]))
        case 3: return .F64(random.pick([0.5, -0.0, .infinity, 1e-300]))
        case 4: return .Boolean(random.chance(50))
        case 5: return .Null
        case 6: return .Bytes(Data((0 ..< random.below(4)).map { _ in UInt8(random.below(256)) }))
        case 7: return .Timestamp(Date(timeIntervalSince1970: TimeInterval(random.below(2_000_000_000))))
        case 8: return .Counter(Int64(random.below(10)))
        default: return .String("s\(random.below(100))")
        }
    }

    private mutating func randomObjectType() -> ObjType {
        random.pick([.Map, .List, .Text])
    }

    /// Every object in the document, root first, in a deterministic order.
    static func objects(in doc: Document) throws -> [(ObjId, ObjType)] {
        var result: [(ObjId, ObjType)] = [(.ROOT, .Map)]
        var index = 0
        while index < result.count {
            let (obj, type) = result[index]
            index += 1
            let children: [Value]
            switch type {
            case .Map: children = try doc.mapEntries(obj: obj).map(\.1)
            case .List: children = try doc.values(obj: obj)
            case .Text: children = []
            }
            for case let .Object(child, childType) in children {
                result.append((child, childType))
            }
        }
        return result
    }
}
