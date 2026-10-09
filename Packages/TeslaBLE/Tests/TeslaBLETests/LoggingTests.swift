import CoreBluetooth
import Foundation
import OSLog
@testable import TeslaBLE
import XCTest

final class LoggingTests: XCTestCase {
    // MARK: - LogMessage rendering

    func testLogMessageRendersScalarsAndDurationsInMilliseconds() {
        let message: LogMessage = "n=\(42) ok=\(true) t=\(Duration.milliseconds(1500))"
        XCTAssertEqual(message.text, "n=42 ok=true t=1500ms")
    }

    func testLogMessageRendersTokenAsFourBytePrefix() {
        let message: LogMessage = "token=\(token: Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02]))"
        XCTAssertEqual(message.text, "token=deadbeef")
    }

    func testLogMessageRendersShortTokenInFull() {
        let message: LogMessage = "token=\(token: Data([0x0A, 0xFF]))"
        XCTAssertEqual(message.text, "token=0aff")
    }

    func testLogMessageRendersLogSafeEnumsByCaseName() {
        let message: LogMessage =
            "\(UniversalMessage_Domain.infotainment) \(ConnectionState.handshaking) \(UniversalMessage_MessageFault_E.rrorBusy)"
        XCTAssertEqual(message.text, "infotainment handshaking rrorBusy")
    }

    func testLogMessageRendersBluetoothManagerStateByName() {
        let message: LogMessage = "\(CBManagerState.poweredOff) \(CBManagerState.unauthorized) \(CBManagerState.poweredOn)"
        XCTAssertEqual(message.text, "poweredOff unauthorized poweredOn")
    }

    func testLogMessageDropsInternalErrorPayload() {
        let error = Dispatcher.Error.decodingFailed("VIN 5YJ3E1EA7KF000000")
        let message: LogMessage = "error=\(error)"
        XCTAssertEqual(message.text, "error=Dispatcher.Error.decodingFailed")
    }

    func testLogMessageDropsPublicErrorPayload() {
        let error = TeslaBLEError.handshakeFailed(underlying: "no private key for VIN 5YJ3E1EA7KF000000")
        let message: LogMessage = "error=\(error)"
        XCTAssertEqual(message.text, "error=TeslaBLEError.handshakeFailed")
    }

    /// Errors that can reach handshake and command logs are named, not
    /// reduced to an opaque `domain code`.
    func testLogMessageNamesHandshakeAndCommandDecodeErrors() {
        let message: LogMessage =
            "\(MetadataHash.Error.valueTooLong(300)) \(ResponseDecoder.Error.decodingFailed("VCSEC_FromVCSECMessage"))"
        XCTAssertEqual(message.text, "MetadataHash.Error.valueTooLong ResponseDecoder.Error.decodingFailed")
    }

    func testLogMessageRendersPayloadFreeErrorCase() {
        let message: LogMessage = "error=\(BLEError.timeout)"
        XCTAssertEqual(message.text, "error=BLEError.timeout")
    }

    func testLogMessageRendersNSErrorAsDomainAndCodeOnly() {
        let error = NSError(domain: "CBErrorDomain", code: 6, userInfo: [NSLocalizedDescriptionKey: "peer 5YJ3E1EA7KF000000"])
        let message: LogMessage = "error=\(error)"
        XCTAssertEqual(message.text, "error=CBErrorDomain 6")
    }

    /// A payload-free case still renders through `String(describing:)`, which
    /// honors custom descriptions — those can carry anything.
    func testLogMessageIgnoresCustomErrorDescriptions() {
        let described: LogMessage = "\(DescribedError.leaky)"
        let debugDescribed: LogMessage = "\(DebugDescribedError.leaky)"
        XCTAssertFalse(described.text.contains("5YJ3E1EA7KF000000"), described.text)
        XCTAssertFalse(debugDescribed.text.contains("deadbeef"), debugDescribed.text)
    }

    /// `Mirror` honors `customMirror`, so even a payload case's label is only
    /// trusted for whitelisted SDK errors.
    func testLogMessageIgnoresCustomMirrorOnUnlistedErrors() {
        let message: LogMessage = "\(ReflectingError.leaky(0))"
        XCTAssertFalse(message.text.contains("5YJ3E1EA7KF000000"), message.text)
    }

    func testLogMessageRendersMissingOptionalErrorAsNone() {
        let error: (any Error)? = nil
        let message: LogMessage = "error=\(error)"
        XCTAssertEqual(message.text, "error=none")
    }

    // MARK: - Log front end

    func testLogForwardsEachLevelWithBoundCategory() {
        let recorder = RecordingLogger()
        let log = Log(recorder, category: .transport)

        log.debug("d=\(1)")
        log.info("i")
        log.warning("w")
        log.error("e")

        XCTAssertEqual(recorder.entries, [
            .init(level: .debug, category: "transport", message: "d=1"),
            .init(level: .info, category: "transport", message: "i"),
            .init(level: .warning, category: "transport", message: "w"),
            .init(level: .error, category: "transport", message: "e"),
        ])
    }

    // MARK: - OSLog backend

    /// `.info` must land at OSLog `notice` so lifecycle events are persisted
    /// on device, `.warning` at `error` so anomalies can be filtered by type,
    /// and message text must be public by default so a collected archive is
    /// readable.
    func testOSLogLoggerPersistsLifecycleAndPublishesTextByDefault() throws {
        let subsystem = "TeslaBLETests.\(UUID().uuidString)"
        let logger = OSLogTeslaBLELogger(subsystem: subsystem)
        let start = Date().addingTimeInterval(-1)

        logger.log(.info, category: "client", "info probe")
        logger.log(.warning, category: "client", "warning probe")
        logger.log(.error, category: "client", "error probe")
        OSLogTeslaBLELogger(subsystem: subsystem, publicMessages: false)
            .log(.info, category: "client", "private probe")

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store
            .getEntries(at: store.position(date: start), matching: NSPredicate(format: "subsystem == %@", subsystem))
            .compactMap { $0 as? OSLogEntryLog }

        XCTAssertEqual(
            entries.map(\.level.rawValue),
            [OSLogEntryLog.Level.notice, .error, .error, .notice].map(\.rawValue),
        )
        // With private-data logging enabled on the host, redaction cannot be
        // observed, so public and private output are indistinguishable.
        try XCTSkipIf(
            entries.last?.composedMessage == "private probe",
            "host logs private data unredacted; cannot verify the public default",
        )
        XCTAssertEqual(
            entries.map(\.composedMessage),
            ["info probe", "warning probe", "error probe", "<private>"],
        )
    }
}

private enum DescribedError: Error, CustomStringConvertible {
    case leaky

    var description: String {
        "vin=5YJ3E1EA7KF000000"
    }
}

private enum DebugDescribedError: Error, CustomDebugStringConvertible {
    case leaky

    var debugDescription: String {
        "key=deadbeef"
    }
}

private enum ReflectingError: Error, CustomReflectable {
    case leaky(Int)

    var customMirror: Mirror {
        Mirror(self, children: ["vin=5YJ3E1EA7KF000000": 0], displayStyle: .enum)
    }
}
