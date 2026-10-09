import CoreBluetooth
import Foundation

/// A value whose rendering is safe to publish in a log line.
///
/// Conform only SDK-owned or system enums whose case names carry no user
/// data. Conforming a type that can hold strings, bytes, or keys breaks the
/// privacy guarantee of ``LogMessage`` — every conformance lives in this file
/// so the whitelist can be reviewed in one place.
protocol LogSafe {
    var logDescription: String { get }
}

extension LogSafe {
    var logDescription: String {
        String(describing: self)
    }
}

/// A log line assembled from a privacy-safe subset of values.
///
/// Literal segments must be `StaticString`, and interpolation only accepts
/// integers, booleans, durations, ``LogSafe`` values, routing-token prefixes,
/// and errors (rendered as type and case name, never the payload).
/// Interpolating a `String`, `Data`, or key type does not compile, so a VIN,
/// message payload, or key cannot reach a ``TeslaBLELogger`` from inside the
/// SDK. That guarantee is what lets ``OSLogTeslaBLELogger`` publish message
/// text by default.
///
/// The remaining escape hatches are explicit at the call site and need review
/// rather than trust: a ``LogSafe`` conformance, `token:` (prints 4 bytes of
/// whatever `Data` it is given), and integers derived from secrets.
struct LogMessage: ExpressibleByStringInterpolation, Sendable {
    let text: String

    init(stringLiteral value: StaticString) {
        text = value.description
    }

    init(stringInterpolation: StringInterpolation) {
        text = stringInterpolation.text
    }

    struct StringInterpolation: StringInterpolationProtocol {
        fileprivate var text = ""

        init(literalCapacity: Int, interpolationCount _: Int) {
            text.reserveCapacity(literalCapacity)
        }

        mutating func appendLiteral(_ literal: StaticString) {
            text += literal.description
        }

        mutating func appendInterpolation(_ value: some BinaryInteger) {
            text += String(value)
        }

        mutating func appendInterpolation(_ value: Bool) {
            text += value ? "true" : "false"
        }

        /// Rendered in whole milliseconds.
        mutating func appendInterpolation(_ value: Duration) {
            let (seconds, attoseconds) = value.components
            text += "\(seconds * 1000 + attoseconds / 1_000_000_000_000_000)ms"
        }

        mutating func appendInterpolation(_ value: some LogSafe) {
            text += value.logDescription
        }

        /// Routing tokens are random, but a 4-byte prefix is all that is
        /// needed to correlate a request with its response.
        mutating func appendInterpolation(token: Data) {
            text += token.prefix(4).map { String(format: "%02x", $0) }.joined()
        }

        mutating func appendInterpolation(_ error: (any Error)?) {
            text += error.map(Self.render) ?? "none"
        }

        /// Whitelisted SDK errors render as `Type.case` with the payload
        /// dropped, since payloads are free-form strings (the VIN can appear
        /// in `TeslaBLEError.handshakeFailed`). Everything else renders as
        /// `domain code`, which excludes `userInfo`: for an arbitrary error,
        /// both `Mirror` (via `customMirror`) and `String(describing:)` (via a
        /// custom description) can be made to say anything.
        private static func render(_ error: any Error) -> String {
            guard error is any LogNamedError else {
                let nsError = error as NSError
                return "\(nsError.domain) \(nsError.code)"
            }
            let qualifiedName = String(reflecting: type(of: error))
            let typeName = qualifiedName.hasPrefix("TeslaBLE.")
                ? String(qualifiedName.dropFirst("TeslaBLE.".count))
                : qualifiedName
            // A case with a payload exposes its name as the child label; a
            // payload-free case renders as its bare name.
            let caseName = Mirror(reflecting: error).children.first?.label ?? String(describing: error)
            return "\(typeName).\(caseName)"
        }
    }
}

// MARK: - Whitelist

/// SDK-owned error enums that may be logged by case name.
///
/// Case names come from `Mirror` and `String(describing:)`, so a conforming
/// type must never customize `description`, `debugDescription`, or
/// `customMirror`. Errors outside this list still log safely, as
/// `domain code`.
protocol LogNamedError: Error {}

extension BLEError: LogNamedError {}
extension Dispatcher.Error: LogNamedError {}
extension RequestTable.Error: LogNamedError {}
extension TeslaBLEError: LogNamedError {}
extension VehicleSession.Error: LogNamedError {}
extension InboundVerifier.Error: LogNamedError {}
extension SessionNegotiator.Error: LogNamedError {}
extension MessageAuthenticator.Error: LogNamedError {}
extension MetadataHash.Error: LogNamedError {}
extension ResponseDecoder.Error: LogNamedError {}
extension P256ECDH.Error: LogNamedError {}
extension VehicleQueryDecoder.Error: LogNamedError {}

extension ConnectionState: LogSafe {}
extension TeslaVehicleClient.ConnectMode: LogSafe {}
extension BLETransport.ConnectionState: LogSafe {}
extension UniversalMessage_Domain: LogSafe {}
extension UniversalMessage_MessageFault_E: LogSafe {}
extension Signatures_Session_Info_Status: LogSafe {}
extension CarServer_OperationStatus_E: LogSafe {}

extension CBManagerState: LogSafe {
    var logDescription: String {
        switch self {
        case .unknown: "unknown"
        case .resetting: "resetting"
        case .unsupported: "unsupported"
        case .unauthorized: "unauthorized"
        case .poweredOff: "poweredOff"
        case .poweredOn: "poweredOn"
        @unknown default: "rawValue(\(rawValue))"
        }
    }
}

extension CBCharacteristicWriteType: LogSafe {
    var logDescription: String {
        switch self {
        case .withResponse: "withResponse"
        case .withoutResponse: "withoutResponse"
        @unknown default: "rawValue(\(rawValue))"
        }
    }
}
