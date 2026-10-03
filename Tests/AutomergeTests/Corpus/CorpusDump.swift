import Automerge
import Foundation

/// A JSON value, written out by `JSONEncoder` with sorted keys and pretty printing. Its output is
/// the same byte for byte on macOS and WASM, so expected files compare as text on every platform.
indirect enum JSONValue: Equatable, Encodable {
    case null
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    var rendered: String {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            return try String(decoding: encoder.encode(self), as: UTF8.self)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .uint(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(values): try container.encode(values)
        case let .object(members): try container.encode(members)
        }
    }
}

/// Lowercase hex for a sequence of bytes.
func hex<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
    let digits = Array("0123456789abcdef")
    var output = ""
    for byte in bytes {
        output.append(digits[Int(byte >> 4)])
        output.append(digits[Int(byte & 0x0F)])
    }
    return output
}

/// A typed, lossless dump of a document's current state and change history, used as the expected
/// output for the golden corpus.
///
/// Every value is tagged with its Automerge type (`{"int": -4}`, `{"counter": 5}`,
/// `{"map": {...}}`), so a value that loads with the wrong type shows up as a difference. Floating
/// point values are written with Swift's shortest round-tripping description, so that NaN and the
/// infinities have a form. Where a map key or list element has conflicting values, the dump lists
/// every value along with the one that wins.
enum CorpusDump {
    static func json(for doc: Document) throws -> JSONValue {
        .object([
            "root": try contents(of: doc),
            "history": .array(doc.getHistory().map { hash in
                guard let change = doc.change(hash: hash) else { return .null }
                return .object([
                    "actor": .string(change.actorId.description.lowercased()),
                    "message": change.message.map(JSONValue.string) ?? .null,
                    "time": .int(Int64(change.timestamp.timeIntervalSince1970)),
                    "deps": .int(Int64(change.deps.count)),
                ])
            }),
        ])
    }

    /// The typed dump of the document's contents alone, without its history. Replicas with the same
    /// changes have the same contents, but may list their history in a different order.
    static func contents(of doc: Document) throws -> JSONValue {
        try object(.ROOT, type: .Map, in: doc)
    }

    /// The untyped JSON that `automerge export` from the Rust CLI produces, for comparing with
    /// output from that tool. Counters and timestamps become plain numbers, text becomes a string,
    /// and bytes become an array of numbers.
    static func exportJSON(for doc: Document) throws -> JSONValue {
        try export(.Object(.ROOT, .Map), in: doc)
    }

    private static func export(_ value: Value, in doc: Document) throws -> JSONValue {
        switch value {
        case let .Object(id, .Map):
            var members: [String: JSONValue] = [:]
            for (key, value) in try doc.mapEntries(obj: id) {
                members[key] = try export(value, in: doc)
            }
            return .object(members)
        case let .Object(id, .List):
            return .array(try doc.values(obj: id).map { try export($0, in: doc) })
        case let .Object(id, .Text):
            return .string(try doc.text(obj: id))
        case let .Scalar(scalar):
            switch scalar {
            case let .Bytes(data): return .array(data.map { .uint(UInt64($0)) })
            case let .String(string): return .string(string)
            case let .Uint(uint): return .uint(uint)
            case let .Int(int): return .int(int)
            case let .F64(double): return .double(double)
            case let .Counter(count): return .int(count)
            case let .Timestamp(date): return .int(Int64((date.timeIntervalSince1970 * 1000).rounded()))
            case let .Boolean(bool): return .bool(bool)
            case let .Unknown(_, data): return .array(data.map { .uint(UInt64($0)) })
            case .Null: return .null
            }
        }
    }

    private static func object(_ id: ObjId, type: ObjType, in doc: Document) throws -> JSONValue {
        switch type {
        case .Map:
            var members: [String: JSONValue] = [:]
            for key in doc.keys(obj: id) {
                members[key] = try entry(
                    winner: doc.get(obj: id, key: key),
                    all: doc.getAll(obj: id, key: key),
                    in: doc
                )
            }
            return .object(["map": .object(members)])
        case .List:
            var elements: [JSONValue] = []
            for index in 0 ..< doc.length(obj: id) {
                try elements.append(entry(
                    winner: doc.get(obj: id, index: index),
                    all: doc.getAll(obj: id, index: index),
                    in: doc
                ))
            }
            return .object(["list": .array(elements)])
        case .Text:
            return .object(["text": .object([
                "value": .string(try doc.text(obj: id)),
                "marks": .array(try doc.marks(obj: id).map { mark in
                    .object([
                        "start": .uint(mark.start),
                        "end": .uint(mark.end),
                        "name": .string(mark.name),
                        "value": scalar(mark.value),
                    ])
                }),
            ])])
        }
    }

    private static func entry(winner: Value?, all: Set<Value>, in doc: Document) throws -> JSONValue {
        guard let winner else { return .null }
        let dumpedWinner = try value(winner, in: doc)
        guard all.count > 1 else { return dumpedWinner }
        let dumpedAll = try all.map { try value($0, in: doc) }
            .sorted { try $0.rendered.utf8.lexicographicallyPrecedes($1.rendered.utf8) }
        return .object(["conflict": .object(["winner": dumpedWinner, "values": .array(dumpedAll)])])
    }

    private static func value(_ value: Value, in doc: Document) throws -> JSONValue {
        switch value {
        case let .Object(id, type):
            return try object(id, type: type, in: doc)
        case let .Scalar(scalarValue):
            return scalar(scalarValue)
        }
    }

    private static func scalar(_ value: ScalarValue) -> JSONValue {
        switch value {
        case let .Bytes(data): return .object(["bytes": .string(hex(data))])
        case let .String(string): return .object(["str": .string(string)])
        case let .Uint(uint): return .object(["uint": .uint(uint)])
        case let .Int(int): return .object(["int": .int(int)])
        case let .F64(double): return .object(["f64": .string(double.description)])
        case let .Counter(count): return .object(["counter": .int(count)])
        case let .Timestamp(date):
            return .object(["timestamp": .int(Int64((date.timeIntervalSince1970 * 1000).rounded()))])
        case let .Boolean(bool): return .object(["bool": .bool(bool)])
        case let .Unknown(typeCode, data):
            return .object(["unknown": .object(["type": .uint(UInt64(typeCode)), "bytes": .string(hex(data))])])
        case .Null: return .object(["null": .null])
        }
    }
}
