import os

/// Severity level for a log message, ordered from most verbose to most severe.
public enum TeslaBLELogLevel: Int, Comparable, Sendable {
    /// High-frequency tracing: every advertisement seen while scanning, every
    /// request sent and response matched.
    case debug = 0
    /// Lifecycle milestones, a handful per session: scan started, vehicle
    /// found, GATT ready, session established, state transitions.
    case info = 1
    /// Recoverable anomalies: request timeouts, vehicle-reported faults,
    /// response verification failures, unexpected BLE disconnects.
    case warning = 2
    /// Failures that end the connect attempt or the session.
    case error = 3

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Sink for internal TeslaBLE diagnostic messages.
///
/// Conform a type to this protocol to route TeslaBLE logs into `OSLog`,
/// a third-party logging framework, or a test double. Pass the conforming
/// value to ``TeslaVehicleClient/init(vin:keyStore:logger:)``.
///
/// The `message` parameter is `@autoclosure` so call sites can build
/// expensive strings inline. Implementations should decide whether to log
/// before evaluating the closure; evaluating it unconditionally defeats
/// the purpose of deferred construction.
///
/// `category` corresponds to an OSLog category and is one of `"client"`,
/// `"dispatcher"`, or `"transport"`.
///
/// Messages never contain the VIN, message payloads, or key material: the
/// SDK builds them from a compile-time whitelist of value types, and errors
/// are rendered without their payload (SDK errors as `Type.case`, any other
/// error as `domain code`).
public protocol TeslaBLELogger: Sendable {
    /// Logs a single message at the given severity and category.
    ///
    /// - Parameters:
    ///   - level: Severity at which the message was emitted.
    ///   - category: Subsystem category, mirroring OSLog conventions.
    ///   - message: Deferred message builder; only evaluate if the logger
    ///     actually intends to record it.
    func log(
        _ level: TeslaBLELogLevel,
        category: String,
        _ message: @autoclosure () -> String,
    )
}

/// Default `TeslaBLELogger` implementation backed by `os.Logger`.
///
/// Levels map onto OSLog types so that everything needed to diagnose a
/// field issue is persisted on device and survives `log collect`:
///
/// | TeslaBLE   | OSLog    | Persisted |
/// |------------|----------|-----------|
/// | `.debug`   | `debug`  | No        |
/// | `.info`    | `notice` | Yes       |
/// | `.warning` | `error`  | Yes       |
/// | `.error`   | `error`  | Yes       |
///
/// Messages below `minimumLevel` are dropped without evaluating the message
/// closure. Message text is logged with `privacy: .public` by default, which
/// is safe because TeslaBLE messages cannot contain the VIN, payloads, or
/// keys (see ``TeslaBLELogger``). The default applies to every string passed
/// to ``log(_:category:_:)``, including an app's own calls. Set
/// `publicMessages` to `false` to have OSLog redact every message as
/// `<private>` outside a debugger.
///
/// Changed after 1.0.0: `.info` previously mapped to OSLog `info` and
/// `.warning` to `notice`, and `publicMessages` defaulted to `false`.
public struct OSLogTeslaBLELogger: TeslaBLELogger {
    private let subsystem: String
    private let minimumLevel: TeslaBLELogLevel
    private let publicMessages: Bool

    /// Creates an OSLog-backed logger.
    ///
    /// - Parameters:
    ///   - subsystem: OSLog subsystem string. Defaults to `"TeslaBLE"`.
    ///   - minimumLevel: Messages below this level are discarded cheaply.
    ///   - publicMessages: When `true` (the default), message text is logged
    ///     with `privacy: .public`; when `false`, with `privacy: .private`.
    public init(
        subsystem: String = "TeslaBLE",
        minimumLevel: TeslaBLELogLevel = .debug,
        publicMessages: Bool = true,
    ) {
        self.subsystem = subsystem
        self.minimumLevel = minimumLevel
        self.publicMessages = publicMessages
    }

    /// Routes a message to `os.Logger`, honoring `minimumLevel` and the
    /// configured privacy mode.
    public func log(
        _ level: TeslaBLELogLevel,
        category: String,
        _ message: @autoclosure () -> String,
    ) {
        guard level >= minimumLevel else { return }
        let logger = Logger(subsystem: subsystem, category: category)
        let text = message()
        if publicMessages {
            logPublic(logger, level: level, text: text)
        } else {
            logPrivate(logger, level: level, text: text)
        }
    }

    private func logPrivate(_ logger: Logger, level: TeslaBLELogLevel, text: String) {
        switch level {
        case .debug: logger.debug("\(text, privacy: .private)")
        case .info: logger.notice("\(text, privacy: .private)")
        case .warning, .error: logger.error("\(text, privacy: .private)")
        }
    }

    private func logPublic(_ logger: Logger, level: TeslaBLELogLevel, text: String) {
        switch level {
        case .debug: logger.debug("\(text, privacy: .public)")
        case .info: logger.notice("\(text, privacy: .public)")
        case .warning, .error: logger.error("\(text, privacy: .public)")
        }
    }
}
