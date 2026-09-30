import Automerge
import Foundation

/// A JSON value with a canonical text form: keys sorted, two-space indentation, and every
/// non-ASCII character written literally. The corpus renders JSON itself, rather than through
/// Foundation, so that expected files compare byte for byte on every platform.
indirect enum CanonicalJSON: Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)
    /// A number written exactly as given.
    case number(String)
    case string(String)
    case array([CanonicalJSON])
    case object([String: CanonicalJSON])

    var rendered: String {
        var output = ""
        render(into: &output, indent: "")
        return output + "\n"
    }

    private func render(into output: inout String, indent: String) {
        let inner = indent + "  "
        switch self {
        case .null:
            output += "null"
        case let .bool(value):
            output += value ? "true" : "false"
        case let .int(value):
            output += String(value)
        case let .uint(value):
            output += String(value)
        case let .number(value):
            output += value
        case let .string(value):
            output += Self.quoted(value)
        case let .array(values):
            guard !values.isEmpty else {
                output += "[]"
                return
            }
            output += "[\n"
            for (index, value) in values.enumerated() {
                output += inner
                value.render(into: &output, indent: inner)
                output += index == values.count - 1 ? "\n" : ",\n"
            }
            output += indent + "]"
        case let .object(members):
            guard !members.isEmpty else {
                output += "{}"
                return
            }
            output += "{\n"
            let keys = members.keys.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
            for (index, key) in keys.enumerated() {
                output += inner + Self.quoted(key) + ": "
                members[key]!.render(into: &output, indent: inner)
                output += index == keys.count - 1 ? "\n" : ",\n"
            }
            output += indent + "}"
        }
    }

    private static func quoted(_ string: String) -> String {
        var output = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case _ where scalar.value < 0x20:
                output += "\\u00" + hex(UInt8(scalar.value))
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        return output + "\""
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

private func hex(_ byte: UInt8) -> String {
    hex([byte])
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
    static func json(for doc: Document) throws -> CanonicalJSON {
        .object([
            "root": try object(.ROOT, type: .Map, in: doc),
            "history": .array(doc.getHistory().map { hash in
                guard let change = doc.change(hash: hash) else { return .null }
                return .object([
                    "actor": .string(change.actorId.description.lowercased()),
                    "message": change.message.map(CanonicalJSON.string) ?? .null,
                    "time": .int(Int64(change.timestamp.timeIntervalSince1970)),
                    "deps": .int(Int64(change.deps.count)),
                ])
            }),
        ])
    }

    /// The untyped JSON that `automerge export` from the Rust CLI produces, for comparing with
    /// output from that tool. Counters and timestamps become plain numbers, text becomes a string,
    /// and bytes become an array of numbers.
    static func exportJSON(for doc: Document) throws -> CanonicalJSON {
        try export(.Object(.ROOT, .Map), in: doc)
    }

    private static func export(_ value: Value, in doc: Document) throws -> CanonicalJSON {
        switch value {
        case let .Object(id, .Map):
            var members: [String: CanonicalJSON] = [:]
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
            case let .F64(double): return .number(double.description)
            case let .Counter(count): return .int(count)
            case let .Timestamp(date): return .int(Int64((date.timeIntervalSince1970 * 1000).rounded()))
            case let .Boolean(bool): return .bool(bool)
            case let .Unknown(_, data): return .array(data.map { .uint(UInt64($0)) })
            case .Null: return .null
            }
        }
    }

    private static func object(_ id: ObjId, type: ObjType, in doc: Document) throws -> CanonicalJSON {
        switch type {
        case .Map:
            var members: [String: CanonicalJSON] = [:]
            for key in doc.keys(obj: id) {
                members[key] = try entry(
                    winner: doc.get(obj: id, key: key),
                    all: doc.getAll(obj: id, key: key),
                    in: doc
                )
            }
            return .object(["map": .object(members)])
        case .List:
            var elements: [CanonicalJSON] = []
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

    private static func entry(winner: Value?, all: Set<Value>, in doc: Document) throws -> CanonicalJSON {
        guard let winner else { return .null }
        let dumpedWinner = try value(winner, in: doc)
        guard all.count > 1 else { return dumpedWinner }
        let dumpedAll = try all.map { try value($0, in: doc) }
            .sorted { $0.rendered.utf8.lexicographicallyPrecedes($1.rendered.utf8) }
        return .object(["conflict": .object(["winner": dumpedWinner, "values": .array(dumpedAll)])])
    }

    private static func value(_ value: Value, in doc: Document) throws -> CanonicalJSON {
        switch value {
        case let .Object(id, type):
            return try object(id, type: type, in: doc)
        case let .Scalar(scalarValue):
            return scalar(scalarValue)
        }
    }

    private static func scalar(_ value: ScalarValue) -> CanonicalJSON {
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
