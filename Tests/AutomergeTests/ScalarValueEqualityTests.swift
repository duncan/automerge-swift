import Automerge
import AutomergeUtilities
import Foundation
import Testing

@Suite("Scalar value equality")
struct ScalarValueEqualityTests {
    static let nans: [Double] = [.nan, -.nan, .signalingNaN, Double(bitPattern: 0x7FF8_0000_0000_0001)]

    @Test("NaN equals NaN, whatever its sign or payload", arguments: nans)
    func nanEqualsNaN(nan: Double) {
        #expect(ScalarValue.F64(nan) == .F64(nan))
        #expect(ScalarValue.F64(nan) == .F64(.nan))
        #expect(ScalarValue.F64(nan).hashValue == ScalarValue.F64(.nan).hashValue)
        #expect(Value.Scalar(.F64(nan)) == .Scalar(.F64(.nan)))
    }

    @Test("NaN doesn't equal numbers, and other doubles compare as Double does")
    func otherDoubles() {
        #expect(ScalarValue.F64(.nan) != .F64(0))
        #expect(ScalarValue.F64(.nan) != .F64(.infinity))
        #expect(ScalarValue.F64(-0.0) == .F64(0.0))
        #expect(ScalarValue.F64(-0.0).hashValue == ScalarValue.F64(0.0).hashValue)
        #expect(ScalarValue.F64(1.5) != .F64(1.25))
    }

    @Test("Values of different types are never equal")
    func differentTypes() {
        let values: [ScalarValue] = [
            .Bytes(Data()), .String(""), .Uint(0), .Int(0), .F64(0), .Counter(0),
            .Timestamp(Date(timeIntervalSince1970: 0)), .Boolean(false), .Unknown(typeCode: 0, data: Data()), .Null,
        ]
        for (i, lhs) in values.enumerated() {
            for (j, rhs) in values.enumerated() {
                #expect((lhs == rhs) == (i == j), "\(lhs) vs \(rhs)")
            }
        }
        #expect(Set(values).count == values.count)
    }

    @Test("A set of values finds a NaN it contains")
    func setContainsNaN() throws {
        let doc = Document()
        try doc.put(obj: .ROOT, key: "value", value: .F64(.nan))
        let values = try doc.getAll(obj: .ROOT, key: "value")
        #expect(values.contains(.Scalar(.F64(.nan))))
    }

    @Test("A document holding NaN has contents equivalent to its fork")
    func documentWithNaNIsEquivalentToFork() throws {
        let doc = Document()
        try doc.put(obj: .ROOT, key: "value", value: .F64(.nan))
        #expect(doc.equivalentContents(doc.fork()))
        #expect(try doc.equivalentContents(Document(doc.save())))
    }
}
