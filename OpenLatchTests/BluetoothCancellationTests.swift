import XCTest
@testable import TeslaBLE

final class BluetoothCancellationTests: XCTestCase, @unchecked Sendable {
    func testCancelledConnectFinishesWithoutStartingDiscovery() async {
        let transport = BLETransport()
        let finished = expectation(description: "Cancelled connection returns")
        let request = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await transport.connect(vin: "5YJ3E1EA0LF000000", timeout: 30)
                XCTFail("A cancelled task must not connect")
            } catch is CancellationError {
                XCTAssertEqual(transport.state, .disconnected)
            } catch {
                XCTFail("Expected cancellation before Bluetooth discovery")
            }
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 3)
        request.cancel()
        transport.disconnect()
    }
}
