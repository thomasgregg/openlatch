import XCTest
import SwiftProtobuf
@testable import TeslaBLE

final class OpenLatchCommandTests: XCTestCase {
    func testEachDoorTargetsExactlyOneClosure() throws {
        for (command, field) in [(Command.Security.unlatchDriverDoor, UInt8(0x08)),
                                  (.unlatchPassengerDoor, 0x10),
                                  (.unlatchRearDriverDoor, 0x18),
                                  (.unlatchRearPassengerDoor, 0x20)] {
            let (domain, body) = try CommandEncoder.encode(.security(command))
            XCTAssertEqual(domain, .vehicleSecurity)
            // Exact wire payload proves no other door, trunk or charge port is requested.
            XCTAssertEqual(body, Data([0x22, 0x02, field, 0x03]))
        }
    }

    func testDriverDoorOnlyWirePayload() throws {
        let (domain, body) = try CommandEncoder.encode(.security(.unlatchDriverDoor))
        XCTAssertEqual(domain, .vehicleSecurity)
        // vcsec.UnsignedMessage closureMoveRequest (field 4),
        // frontDriverDoor (field 1), OPEN (enum 3): 22 02 08 03.
        XCTAssertEqual(body, Data([0x22, 0x02, 0x08, 0x03]))
        let message = try VCSEC_UnsignedMessage(serializedBytes: body)
        XCTAssertEqual(message.closureMoveRequest.frontDriverDoor, .closureMoveTypeOpen)
        XCTAssertEqual(message.closureMoveRequest.frontPassengerDoor, .closureMoveTypeNone)
        XCTAssertEqual(message.closureMoveRequest.rearTrunk, .closureMoveTypeNone)
    }
}
