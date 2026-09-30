import Automerge
import Foundation
import Testing

extension CanonicalJSON: Encodable {
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(v): try c.encode(v)
        case let .int(v): try c.encode(v)
        case let .uint(v): try c.encode(v)
        case let .number(v): try c.encode(Double(v)!)
        case let .string(v): try c.encode(v)
        case let .array(v): try c.encode(v)
        case let .object(v): try c.encode(v)
        }
    }
}

@Test(arguments: GoldenRecipe.all)
func encoderOutputMatchesMacOS(recipe: GoldenRecipe) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    let doc = try Document(Corpus.data("golden/\(recipe.name).automerge"))
    let output = try encoder.encode(CorpusDump.json(for: doc))
    let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    let macOS = try Data(contentsOf: fixtures.appendingPathComponent("Probe/\(recipe.name).json"))
    if output != macOS {
        Issue.record("PROBE-MISMATCH \(recipe.name):\n\(String(decoding: output, as: UTF8.self))")
    }
}

@Test(arguments: GoldenRecipe.all)
func decodedJSONMatches(recipe: GoldenRecipe) throws {
    // Option (b): compare parsed structures, ignoring formatting.
    let expected = try JSONSerialization.jsonObject(with: Corpus.data("golden/\(recipe.name).json")) as? NSDictionary
    let doc = try Document(Corpus.data("golden/\(recipe.name).automerge"))
    let actual = try JSONSerialization.jsonObject(with: Data(CorpusDump.json(for: doc).rendered.utf8)) as? NSDictionary
    #expect(expected != nil)
    #expect(expected == actual)
}
