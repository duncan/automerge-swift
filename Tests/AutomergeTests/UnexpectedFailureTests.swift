@testable import Automerge
import Foundation
import Testing

/// When the Rust library panics during a throwing call, UniFFI reports it with its own error type,
/// which isn't public. These check that such an error reaches callers as the public error the call
/// throws otherwise. No call is known to panic, so an unknown error stands in for UniFFI's.
@Suite("Unexpected failures")
struct UnexpectedFailureTests {
    struct StandIn: Error, CustomStringConvertible {
        var description: String { "rustPanic(\"simulated\")" }
    }

    @Test("An unexpected failure throws the call's own error type, with an internal case")
    func mapsToPublicErrors() throws {
        let doc = #expect(throws: DocError.self) { try wrappedErrors { throw StandIn() } }
        let load = #expect(throws: LoadError.self) { try wrappedErrors(unexpected: .load) { throw StandIn() } }
        let receive = #expect(throws: ReceiveSyncError.self) {
            try wrappedErrors(unexpected: .receiveSync) { throw StandIn() }
        }
        let decode = #expect(throws: DecodeSyncStateError.self) {
            try wrappedErrors(unexpected: .decodeSyncState) { throw StandIn() }
        }

        if case let .Internal(message)? = doc?.inner { #expect(message.contains("rustPanic(\"simulated\")")) }
        else { Issue.record("expected DocError.Internal, got \(String(describing: doc))") }
        if case let .Internal(message)? = load?.inner { #expect(message.contains("simulated")) }
        else { Issue.record("expected LoadError.Internal, got \(String(describing: load))") }
        if case let .Internal(message)? = receive?.inner { #expect(message.contains("simulated")) }
        else { Issue.record("expected ReceiveSyncError.Internal, got \(String(describing: receive))") }
        if case let .Internal(message)? = decode?.inner { #expect(message.contains("simulated")) }
        else { Issue.record("expected DecodeSyncStateError.Internal, got \(String(describing: decode))") }
    }

    @Test("The description says the failure was unexpected")
    func describesFailure() {
        let error = UnexpectedFailure.doc.error(StandIn())
        #expect((error as? DocError)?.localizedDescription.contains("automerge failed unexpectedly") == true)
    }

    @Test("Known errors still map to their own types")
    func knownErrorsUnchanged() throws {
        let doc = Document()
        let list = try doc.putObject(obj: .ROOT, key: "list", ty: .List)
        let error = #expect(throws: DocError.self) { try doc.put(obj: list, key: "a", value: .Int(1)) }
        if case .WrongObjectType? = error?.inner {} else { Issue.record("expected WrongObjectType, got \(String(describing: error))") }
        #expect(throws: LoadError.self) { try Document(Data([0x00])) }
        #expect(throws: DecodeSyncStateError.self) { try SyncState(bytes: Data([0x00])) }
        #expect(throws: ReceiveSyncError.self) {
            try doc.receiveSyncMessage(state: SyncState(), message: Data([0x42, 0x00]))
        }
    }
}
