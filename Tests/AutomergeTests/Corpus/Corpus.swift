import Foundation
import Testing

/// Access to the binary fixtures under `Fixtures/Corpus`, which the test target bundles as resources.
enum Corpus {
    struct MissingFixtures: Error {}

    /// The `Fixtures/Corpus` directory inside the test bundle.
    static func directory() throws -> URL {
        guard let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            throw MissingFixtures()
        }
        return fixtures.appendingPathComponent("Corpus")
    }

    /// The contents of the fixture at `path`, relative to `Fixtures/Corpus`.
    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: directory().appendingPathComponent(path))
    }

    /// The names of the files in `subdirectory`, relative to `Fixtures/Corpus`, sorted and excluding hidden files.
    static func fileNames(in subdirectory: String) throws -> [String] {
        let url = try directory().appendingPathComponent(subdirectory)
        return try FileManager.default.contentsOfDirectory(atPath: url.path)
            .filter { !$0.hasPrefix(".") && $0 != "README.md" }
            .sorted()
    }
}
