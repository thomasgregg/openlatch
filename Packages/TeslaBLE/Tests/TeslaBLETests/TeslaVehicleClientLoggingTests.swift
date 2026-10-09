@testable import TeslaBLE
import XCTest

final class TeslaVehicleClientLoggingTests: XCTestCase {
    /// The key-load failure carries the VIN in its error payload
    /// (`handshakeFailed("no private key for VIN …")`); the log must name the
    /// failing stage without it.
    func testConnectWithoutKeyLogsKeyLoadFailureWithoutVIN() async throws {
        let vin = "5YJ3E1EA7KF000000"
        let recorder = RecordingLogger()
        let client = TeslaVehicleClient(vin: vin, keyStore: InMemoryTeslaKeyStore(), logger: recorder)

        do {
            try await client.connect()
            XCTFail("expected connect to fail without a stored key")
        } catch {}

        let failure = try XCTUnwrap(recorder.entries.first { $0.level == .error }, "\(recorder.entries)")
        XCTAssertEqual(failure.category, "client")
        XCTAssertTrue(failure.message.contains("keyLoad"), failure.message)
        XCTAssertEqual(recorder.entries.filter { $0.message.contains(vin) }, [])
    }
}
