@testable import Automerge
import Foundation
import XCTest

/// When the Rust library panics during a throwing call, UniFFI reports it with its own error type,
/// which isn't public. These check that such an error reaches callers as the public error the call
/// throws otherwise. No call is known to panic, so an unknown error stands in for UniFFI's.
class UnexpectedFailureTests: XCTestCase {
    struct StandIn: Error, CustomStringConvertible {
        var description: String { "rustPanic(\"simulated\")" }
    }

    func testUnexpectedFailureThrowsTheCallsOwnErrorTypeWithAnInternalCase() {
        XCTAssertThrowsError(try wrappedErrors { () throws -> Void in throw StandIn() }) { error in
            guard case let .Internal(message)? = (error as? DocError)?.inner else {
                return XCTFail("expected DocError.Internal, got \(error)")
            }
            XCTAssertTrue(message.contains("rustPanic(\"simulated\")"), message)
        }
        XCTAssertThrowsError(try wrappedErrors(unexpected: .load) { () throws -> Void in throw StandIn() }) { error in
            guard case let .Internal(message)? = (error as? LoadError)?.inner else {
                return XCTFail("expected LoadError.Internal, got \(error)")
            }
            XCTAssertTrue(message.contains("simulated"), message)
        }
        XCTAssertThrowsError(
            try wrappedErrors(unexpected: .receiveSync) { () throws -> Void in throw StandIn() }
        ) { error in
            guard case let .Internal(message)? = (error as? ReceiveSyncError)?.inner else {
                return XCTFail("expected ReceiveSyncError.Internal, got \(error)")
            }
            XCTAssertTrue(message.contains("simulated"), message)
        }
        XCTAssertThrowsError(
            try wrappedErrors(unexpected: .decodeSyncState) { () throws -> Void in throw StandIn() }
        ) { error in
            guard case let .Internal(message)? = (error as? DecodeSyncStateError)?.inner else {
                return XCTFail("expected DecodeSyncStateError.Internal, got \(error)")
            }
            XCTAssertTrue(message.contains("simulated"), message)
        }
    }

    func testDescriptionSaysTheFailureWasUnexpected() {
        let error = UnexpectedFailure.doc.error(StandIn())
        XCTAssertEqual((error as? DocError)?.localizedDescription.contains("automerge failed unexpectedly"), true)
    }

    func testKnownErrorsStillMapToTheirOwnTypes() throws {
        let doc = Document()
        let list = try doc.putObject(obj: .ROOT, key: "list", ty: .List)
        XCTAssertThrowsError(try doc.put(obj: list, key: "a", value: .Int(1))) { error in
            guard case .WrongObjectType? = (error as? DocError)?.inner else {
                return XCTFail("expected WrongObjectType, got \(error)")
            }
        }
        XCTAssertThrowsError(try Document(Data([0x00]))) { error in
            XCTAssertTrue(error is LoadError, "expected LoadError, got \(error)")
        }
        XCTAssertThrowsError(try SyncState(bytes: Data([0x00]))) { error in
            XCTAssertTrue(error is DecodeSyncStateError, "expected DecodeSyncStateError, got \(error)")
        }
        XCTAssertThrowsError(try doc.receiveSyncMessage(state: SyncState(), message: Data([0x42, 0x00]))) { error in
            XCTAssertTrue(error is ReceiveSyncError, "expected ReceiveSyncError, got \(error)")
        }
    }
}
