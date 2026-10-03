import Automerge
import Foundation
import Testing

/// The documents in the golden corpus, and how to build each one from the Swift API.
///
/// Recipes pin every actor and change timestamp, so building one twice produces the same bytes. That
/// lets the tests check both directions: the checked-in bytes still load to the expected contents, and
/// building the document today still saves to the checked-in bytes.
///
/// Don't change an existing recipe: its checked-in bytes are what older versions of this package saved,
/// and loading them is part of what the corpus tests. Add a new recipe instead.
struct GoldenRecipe: Sendable, CustomTestStringConvertible {
    let name: String
    let build: @Sendable () throws -> Document

    var testDescription: String { name }

    static let all: [GoldenRecipe] = [
        GoldenRecipe(name: "scalars", build: scalars),
        GoldenRecipe(name: "nested", build: nested),
        GoldenRecipe(name: "text", build: text),
        GoldenRecipe(name: "conflicts", build: conflicts),
        GoldenRecipe(name: "history", build: history),
    ]
}

private func actor(_ byte: UInt8) -> ActorId {
    ActorId(data: Data(repeating: byte, count: 16))!
}

/// 2024-01-01T00:00:00Z, in seconds.
private let baseTime: TimeInterval = 1_704_067_200

private func commit(_ doc: Document, _ message: String?, at offset: TimeInterval = 0) {
    doc.commitWith(message: message, timestamp: Date(timeIntervalSince1970: baseTime + offset))
}

/// One key for every scalar type, including the edges of each numeric range.
@Sendable private func scalars() throws -> Document {
    let doc = Document()
    doc.actor = actor(0xA1)
    let values: [(String, ScalarValue)] = [
        ("str", .String("Hello 🇬🇧👨‍👨‍👧‍👦😀 e\u{301}")),
        ("str_empty", .String("")),
        ("str_escapes", .String("quote \" backslash \\ newline \n tab \t nul \u{0}")),
        ("int_min", .Int(.min)),
        ("int_max", .Int(.max)),
        ("int_zero", .Int(0)),
        ("int_negative", .Int(-4)),
        ("uint_max", .Uint(.max)),
        ("uint_zero", .Uint(0)),
        ("f64_pi", .F64(3.14159267)),
        ("f64_negative_zero", .F64(-0.0)),
        ("f64_infinity", .F64(.infinity)),
        ("f64_negative_infinity", .F64(-.infinity)),
        ("f64_nan", .F64(.nan)),
        ("f64_subnormal", .F64(.leastNonzeroMagnitude)),
        ("f64_max", .F64(.greatestFiniteMagnitude)),
        ("bool_true", .Boolean(true)),
        ("bool_false", .Boolean(false)),
        ("null", .Null),
        ("bytes", .Bytes(Data([0x85, 0x6F, 0x4A, 0x83]))),
        ("bytes_empty", .Bytes(Data())),
        ("timestamp", .Timestamp(Date(timeIntervalSince1970: -905_182_979))),
        ("timestamp_epoch", .Timestamp(Date(timeIntervalSince1970: 0))),
        ("counter", .Counter(10)),
    ]
    for (key, value) in values {
        try doc.put(obj: .ROOT, key: key, value: value)
    }
    commit(doc, "scalars")

    try doc.increment(obj: .ROOT, key: "counter", by: 5)
    try doc.increment(obj: .ROOT, key: "counter", by: -8)
    commit(doc, "increment the counter", at: 60)
    return doc
}

/// Maps, lists and text nested inside each other, including empty ones, and deletions from each.
@Sendable private func nested() throws -> Document {
    let doc = Document()
    doc.actor = actor(0xB2)
    let config = try doc.putObject(obj: .ROOT, key: "config", ty: .Map)
    try doc.put(obj: config, key: "name", value: .String("corpus"))
    try doc.put(obj: config, key: "removed", value: .Boolean(true))
    let items = try doc.putObject(obj: config, key: "items", ty: .List)
    for (index, word) in ["alpha", "beta", "gamma", "delta"].enumerated() {
        try doc.insert(obj: items, index: UInt64(index), value: .String(word))
    }
    let item = try doc.insertObject(obj: items, index: 2, ty: .Map)
    try doc.put(obj: item, key: "id", value: .Uint(7))
    let tags = try doc.putObject(obj: item, key: "tags", ty: .List)
    try doc.insert(obj: tags, index: 0, value: .String("x"))
    let inner = try doc.insertObject(obj: tags, index: 1, ty: .List)
    try doc.insert(obj: inner, index: 0, value: .Int(1))
    try doc.insert(obj: inner, index: 1, value: .Null)
    let note = try doc.putObject(obj: item, key: "note", ty: .Text)
    try doc.spliceText(obj: note, start: 0, delete: 0, value: "nested text")
    _ = try doc.putObject(obj: .ROOT, key: "empty_map", ty: .Map)
    _ = try doc.putObject(obj: .ROOT, key: "empty_list", ty: .List)
    _ = try doc.putObject(obj: .ROOT, key: "empty_text", ty: .Text)
    commit(doc, "build")

    try doc.delete(obj: config, key: "removed")
    try doc.delete(obj: items, index: 1)
    try doc.splice(obj: items, start: 3, delete: 1, values: [.String("epsilon"), .Int(-1)])
    try doc.put(obj: items, index: 0, value: .String("ALPHA"))
    commit(doc, "edit", at: 60)
    return doc
}

/// Text with multi-scalar grapheme clusters, edits in the middle, and marks of each expand kind,
/// one of them removed again.
@Sendable private func text() throws -> Document {
    let doc = Document()
    doc.actor = actor(0xC3)
    let text = try doc.putObject(obj: .ROOT, key: "text", ty: .Text)
    try doc.spliceText(obj: text, start: 0, delete: 0, value: "Hello 🇬🇧 world 👨‍👨‍👧‍👦!")
    commit(doc, "write")

    // Replace "world" with "wide wo\u{301}rld" (combining acute accent).
    try doc.spliceText(obj: text, start: 9, delete: 5, value: "wide wo\u{301}rld")
    try doc.spliceText(obj: text, start: 0, delete: 0, value: "¡")
    try doc.mark(obj: text, start: 1, end: 6, expand: .none, name: "bold", value: .Boolean(true))
    try doc.mark(obj: text, start: 7, end: 9, expand: .both, name: "flag", value: .String("GB"))
    try doc.mark(obj: text, start: 10, end: 14, expand: .before, name: "italic", value: .Boolean(true))
    try doc.mark(obj: text, start: 15, end: 21, expand: .after, name: "link", value: .String("https://automerge.org/"))
    try doc.mark(obj: text, start: 1, end: 4, expand: .none, name: "size", value: .Int(12))
    commit(doc, "edit and mark", at: 60)

    try doc.mark(obj: text, start: 1, end: 4, expand: .none, name: "size", value: .Null)
    try doc.updateText(obj: text, value: "¡Hello 🇬🇧 wide wo\u{301}rld 👨‍👨‍👧‍👦!?")
    commit(doc, "unmark and update", at: 120)
    return doc
}

/// Two actors making concurrent, conflicting changes that are then merged.
@Sendable private func conflicts() throws -> Document {
    let doc = Document()
    doc.actor = actor(0xD4)
    try doc.put(obj: .ROOT, key: "title", value: .String("base"))
    try doc.put(obj: .ROOT, key: "count", value: .Counter(0))
    let list = try doc.putObject(obj: .ROOT, key: "list", ty: .List)
    try doc.insert(obj: list, index: 0, value: .String("first"))
    let doomed = try doc.putObject(obj: .ROOT, key: "doomed", ty: .Map)
    try doc.put(obj: doomed, key: "value", value: .Int(1))
    let text = try doc.putObject(obj: .ROOT, key: "text", ty: .Text)
    try doc.spliceText(obj: text, start: 0, delete: 0, value: "ab")
    commit(doc, "base")

    let other = doc.fork()
    other.actor = actor(0xE5)

    // The same key set to different values and types.
    try doc.put(obj: .ROOT, key: "title", value: .String("from D4"))
    try other.put(obj: .ROOT, key: "title", value: .Int(42))
    // Concurrent increments add up.
    try doc.increment(obj: .ROOT, key: "count", by: 3)
    try other.increment(obj: .ROOT, key: "count", by: 4)
    // Inserts at the same index both survive, in a deterministic order.
    try doc.insert(obj: list, index: 1, value: .String("from D4"))
    try other.insert(obj: list, index: 1, value: .String("from E5"))
    // The same list element set to different values.
    try doc.put(obj: list, index: 0, value: .String("first from D4"))
    try other.put(obj: list, index: 0, value: .String("first from E5"))
    // A deleted map racing an edit inside it.
    try doc.delete(obj: .ROOT, key: "doomed")
    try other.put(obj: doomed, key: "value", value: .Int(2))
    // Concurrent text inserts at the same position.
    try doc.spliceText(obj: text, start: 1, delete: 0, value: "D")
    try other.spliceText(obj: text, start: 1, delete: 0, value: "E")
    // A key only one side creates, set to an object on one side and a scalar on the other.
    _ = try doc.putObject(obj: .ROOT, key: "shape", ty: .Map)
    try other.put(obj: .ROOT, key: "shape", value: .String("circle"))
    commit(doc, "D4 edits", at: 60)
    commit(other, "E5 edits", at: 61)

    try doc.merge(other: other)
    return doc
}

/// A linear history of commits with and without messages, overwriting and deleting the same key.
@Sendable private func history() throws -> Document {
    let doc = Document()
    doc.actor = actor(0xF6)
    try doc.put(obj: .ROOT, key: "status", value: .String("draft"))
    commit(doc, "create")
    try doc.put(obj: .ROOT, key: "status", value: .String("review"))
    commit(doc, nil, at: 3600)
    try doc.put(obj: .ROOT, key: "status", value: .String("published"))
    try doc.put(obj: .ROOT, key: "temporary", value: .Boolean(true))
    commit(doc, "", at: 7200)
    try doc.delete(obj: .ROOT, key: "temporary")
    commit(doc, "remove temporary 🗑️", at: 86400)
    return doc
}
