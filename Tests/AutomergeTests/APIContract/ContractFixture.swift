@testable import Automerge
import Foundation
import Testing

/// A document with one object of each type, for checking how the API responds to misuse.
struct ContractFixture {
    let doc = Document()
    /// A list containing `"a"`, `"b"`, `"c"`.
    let list: ObjId
    /// Text containing `"hello"`.
    let text: ObjId
    /// A map containing `k: 1`.
    let map: ObjId

    init() throws {
        list = try doc.putObject(obj: .ROOT, key: "list", ty: .List)
        for (index, value) in ["a", "b", "c"].enumerated() {
            try doc.insert(obj: list, index: UInt64(index), value: .String(value))
        }
        text = try doc.putObject(obj: .ROOT, key: "text", ty: .Text)
        try doc.spliceText(obj: text, start: 0, delete: 0, value: "hello")
        map = try doc.putObject(obj: .ROOT, key: "map", ty: .Map)
        try doc.put(obj: map, key: "k", value: .Int(1))
        try doc.put(obj: .ROOT, key: "string", value: .String("s"))
        try doc.put(obj: .ROOT, key: "count", value: .Counter(1))
        doc.commitWith(message: nil, timestamp: Date(timeIntervalSince1970: 0))
    }

    /// Runs `operation`, which must throw a `DocError` for which `matches` is true, and checks that
    /// the document is unchanged afterwards, including after committing.
    func expectRejected(
        _ matches: (FfiDocError) -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ operation: (ContractFixture) throws -> Void
    ) throws {
        let heads = doc.heads()
        let before = try CorpusDump.contents(of: doc)
        do {
            try operation(self)
            Issue.record("expected a DocError", sourceLocation: sourceLocation)
        } catch let error as DocError {
            #expect(matches(error.inner), "unexpected error: \(error.inner)", sourceLocation: sourceLocation)
        } catch {
            Issue.record("expected a DocError, got \(error)", sourceLocation: sourceLocation)
        }
        doc.commitWith(message: nil, timestamp: Date(timeIntervalSince1970: 1))
        #expect(doc.heads() == heads, "the document gained a change", sourceLocation: sourceLocation)
        #expect(try CorpusDump.contents(of: doc) == before, sourceLocation: sourceLocation)
    }
}

extension FfiDocError {
    var isWrongObjectType: Bool {
        if case .WrongObjectType = self { return true }
        return false
    }

    /// Whether this is the error automerge reports for an index past the end of an object.
    var isOutOfBounds: Bool {
        if case let .Internal(message) = self { return message.contains("is out of bounds") }
        return false
    }

    func isInternal(containing text: String) -> Bool {
        if case let .Internal(message) = self { return message.contains(text) }
        return false
    }
}

/// An operation for a parameterized test, with a name to show in the test results.
struct NamedOperation: CustomTestStringConvertible, Sendable {
    let name: String
    let run: @Sendable (ContractFixture) throws -> Void

    init(_ name: String, _ run: @escaping @Sendable (ContractFixture) throws -> Void) {
        self.name = name
        self.run = run
    }

    var testDescription: String { name }
}
