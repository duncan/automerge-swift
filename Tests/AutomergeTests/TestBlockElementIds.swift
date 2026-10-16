@testable import Automerge
import XCTest

class BlockElementIdsTestCase: XCTestCase {
    func testABlockMarkerIsOneElement() throws {
        for encoding in [TextEncoding.utf8, .utf16, .unicodeScalar] {
            let doc = Document(textEncoding: encoding)
            let text = try doc.putObject(obj: ObjId.ROOT, key: "text", ty: .Text)
            try doc.spliceText(obj: text, start: 0, delete: 0, value: "ab")
            _ = try doc.splitBlock(obj: text, index: 1)
            let length = doc.length(obj: text)

            let ids = try doc.elementIds(obj: text, range: 0 ..< length)
            XCTAssertEqual(ids.count, 3, "\(encoding)")
            // The marker counts as the object replacement character does in the encoding, as the core counts it.
            XCTAssertEqual(try ids.map { try doc.position(obj: text, elementId: $0) }, [0, 1, length - 1], "\(encoding)")

            try doc.joinBlock(obj: text, index: 1)
            XCTAssertNil(try doc.position(obj: text, elementId: ids[1]), "\(encoding)")
            XCTAssertEqual(try doc.position(obj: text, elementId: ids[2]), 1, "\(encoding)")
        }
    }
}
