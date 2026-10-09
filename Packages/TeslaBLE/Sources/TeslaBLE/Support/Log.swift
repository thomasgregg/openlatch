/// SDK-internal front end for ``TeslaBLELogger``.
///
/// Binds one category per component and accepts only ``LogMessage``, so every
/// internal call site goes through the privacy whitelist.
///
/// Level policy:
/// - `debug`: high-frequency tracing (per advertisement, per request).
/// - `info`: lifecycle milestones, a handful per session.
/// - `warning`: recoverable anomalies (timeouts, faults, unexpected drops).
/// - `error`: failures that end the session or the connect attempt.
struct Log: Sendable {
    enum Category: String, Sendable {
        case client
        case dispatcher
        case transport
    }

    private let sink: (any TeslaBLELogger)?
    private let category: Category

    init(_ sink: (any TeslaBLELogger)?, category: Category) {
        self.sink = sink
        self.category = category
    }

    func debug(_ message: @autoclosure () -> LogMessage) {
        emit(.debug, message)
    }

    func info(_ message: @autoclosure () -> LogMessage) {
        emit(.info, message)
    }

    func warning(_ message: @autoclosure () -> LogMessage) {
        emit(.warning, message)
    }

    func error(_ message: @autoclosure () -> LogMessage) {
        emit(.error, message)
    }

    private func emit(_ level: TeslaBLELogLevel, _ message: () -> LogMessage) {
        sink?.log(level, category: category.rawValue, message().text)
    }
}
