import Foundation
@testable import TeslaBLE

/// `TeslaBLELogger` that captures every call so tests can assert on the
/// level, category, and rendered text the SDK emits.
final class RecordingLogger: TeslaBLELogger, @unchecked Sendable {
    struct Entry: Equatable {
        let level: TeslaBLELogLevel
        let category: String
        let message: String
    }

    private let lock = NSLock()
    private var recorded: [Entry] = []

    var entries: [Entry] {
        lock.withLock { recorded }
    }

    func log(
        _ level: TeslaBLELogLevel,
        category: String,
        _ message: @autoclosure () -> String,
    ) {
        let entry = Entry(level: level, category: category, message: message())
        lock.withLock { recorded.append(entry) }
    }
}
