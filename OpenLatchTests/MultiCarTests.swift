import XCTest
import UIKit
import AppIntents
import OpenLatchCore
@testable import OpenLatch

@MainActor
private final class RecordingVehicleService: VehicleService {
    var connectedValue = true
    var connected: Bool { get async { connectedValue } }
    var opened: [String] = []
    var openedDoors: [VehicleDoor] = []
    var deleted: [String] = []
    var connectionDelay: Duration = .zero
    var connectedVIN: String?
    var pairDelay: Duration = .milliseconds(20)
    var pairFailure: VehicleIssue?
    var deleteFailure: VehicleIssue?
    func pair(vin: String) async throws {
        try await Task.sleep(for: pairDelay)
        if let pairFailure { throw pairFailure }
    }
    func connect(vin: String) async throws {
        try await Task.sleep(for: connectionDelay)
        connectedVIN = vin
    }
    func openDoor(vin: String, door: VehicleDoor) async throws -> DoorOutcome {
        opened.append(vin)
        openedDoors.append(door)
        try await Task.sleep(for: .milliseconds(100))
        return .confirmedOpen
    }
    func disconnect() async {}
    func deleteLocalKey(vin: String) throws {
        if let deleteFailure { throw deleteFailure }
        deleted.append(vin)
    }
}

@MainActor
final class MultiCarTests: XCTestCase {
    func testDefaultDoorAndOneOffOverrideTargetCorrectDoorWithoutChangingAnotherCar() async throws {
        let service = RecordingVehicleService()
        let model = model(service)
        defer { model.pause() }
        model.setDefaultDoor(.passenger, vin: second.vin)
        XCTAssertEqual(model.profile?.vin, first.vin)
        XCTAssertEqual(model.profile?.defaultDoor, .driver)
        XCTAssertTrue(model.selectCar(vin: second.vin))
        model.openDoor()
        try await finish(model)
        model.openDoor(.rearDriver)
        try await finish(model)
        XCTAssertEqual(model.profile?.defaultDoor, .passenger)
        _ = try await model.openFromShortcut(vin: second.vin)
        _ = try await model.openFromShortcut(vin: second.vin, door: nil)
        _ = try await model.openFromShortcut(vin: second.vin, door: .rearPassenger)
        XCTAssertEqual(service.opened, Array(repeating: second.vin, count: 5))
        XCTAssertEqual(service.openedDoors, [.passenger, .rearDriver, .driver, .passenger, .rearPassenger])
        XCTAssertEqual(model.garage.vehicles.first?.defaultDoor, .driver)
    }

    func testShortcutsHaveExplicitDoorPresetsAndAvailableDoorSymbols() throws {
        XCTAssertEqual(OpenLatchShortcuts.appShortcuts.count, 5)
        XCTAssertEqual(OpenDoorIntent().door, .defaultDoor)
        for door in OpenLatchDoor.allCases {
            let intent = OpenDoorIntent(door: door)
            XCTAssertEqual(intent.door, door)
            if let vehicleDoor = door.vehicleDoor {
                XCTAssertNotNil(UIImage(systemName: vehicleDoor.symbolName))
            }
        }
        XCTAssertNotNil(UIImage(systemName: "car.top.door.front.left.and.front.right.open"))
    }

    func testDefaultDoorCannotChangeDuringPhysicalRequest() async throws {
        let service = RecordingVehicleService()
        let model = model(service)
        defer { model.pause() }
        model.openDoor()
        model.setDefaultDoor(.passenger, vin: first.vin)
        XCTAssertEqual(model.profile?.defaultDoor, .driver)
        try await finish(model)
        XCTAssertEqual(service.openedDoors, [.driver])
    }

    func testApprovedArtworkIsBundledWithAConsistentCanvas() throws {
        for value in VehicleModel.allCases where value != .unknown {
            let image = try XCTUnwrap(UIImage(named: "CarFront-\(value.rawValue)"), value.displayName)
            XCTAssertEqual(image.size, CGSize(width: 640, height: 480))
            XCTAssertNotNil(image.cgImage)
        }
    }

    func testChangingCarsAutomaticallyChangesTheModelWithoutChangingKeys() {
        let service = RecordingVehicleService()
        let truck = VehicleProfile(vin: "7G2CEHED0SA000000", paired: true, tested: true, onboardingComplete: true)
        let model = AppModel(testService: service, testGarage: VehicleGarage(vehicles: [first, truck], selectedVIN: first.vin))
        defer { model.pause() }
        XCTAssertEqual(model.profile?.vehicleModel, .model3)
        XCTAssertTrue(model.selectCar(vin: truck.vin))
        XCTAssertEqual(model.profile?.vehicleModel, .cybertruck)
        XCTAssertTrue(model.selectCar(vin: first.vin))
        XCTAssertEqual(model.profile, first)
        XCTAssertTrue(service.deleted.isEmpty)
    }

    private let first = VehicleProfile(vin: "5YJ3E1EA0LF000000", name: "Atlas", paired: true,
                                       tested: true, onboardingComplete: true)
    private let second = VehicleProfile(vin: "5YJ3E1EA0LF000001", name: "Bluebird", paired: true,
                                        tested: true, onboardingComplete: true)

    private func model(_ service: RecordingVehicleService) -> AppModel {
        AppModel(testService: service, testGarage: VehicleGarage(vehicles: [first, second], selectedVIN: first.vin))
    }
    private func finish(_ model: AppModel) async throws {
        for _ in 0..<200 {
            if !model.busy { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Operation did not finish")
    }

    func testDuplicateVINAndRenameDoNotOverwriteAnotherCar() {
        let model = model(RecordingVehicleService())
        defer { model.pause() }
        model.addCar()
        model.vinInput = second.vin.lowercased()
        model.identify()
        XCTAssertEqual(model.garage.vehicles.count, 2)
        XCTAssertEqual(model.profile?.vin, second.vin)
        XCTAssertEqual(model.screen, .everyday)
        XCTAssertTrue(model.rename("New nickname"))
        XCTAssertEqual(model.garage.vehicles.first, first)
        XCTAssertEqual(model.profile?.name, "New nickname")
    }

    func testCancellingSecondCarSetupPreservesItsKeyAndFirstCar() async throws {
        let service = RecordingVehicleService()
        let model = model(service)
        defer { model.pause() }
        model.addCar()
        model.vinInput = "5YJ3E1EA0LF000002"
        model.identify()
        model.startPairing()
        try await finish(model)
        XCTAssertEqual(model.screen, .test)
        model.backToConnect()
        model.leaveSetup()
        XCTAssertEqual(model.profile, first)
        XCTAssertEqual(model.garage.vehicles.count, 3)
        XCTAssertEqual(model.garage.vehicles.last?.nextScreen, .test)
        XCTAssertTrue(service.deleted.isEmpty)
    }

    func testRemovingSelectedCarOnlyDeletesItsKey() async throws {
        let service = RecordingVehicleService()
        let model = model(service)
        defer { model.pause() }
        XCTAssertTrue(model.selectCar(vin: second.vin))
        model.removeKey()
        try await finish(model)
        XCTAssertEqual(service.deleted, [second.vin])
        XCTAssertEqual(model.garage.vehicles, [first])
        XCTAssertEqual(model.profile, first)
        XCTAssertEqual(model.screen, .everyday)
    }

    func testRemovingCarCancelsOfflineReconnect() async throws {
        let service = RecordingVehicleService()
        service.connectedValue = false
        service.connectionDelay = .seconds(30)
        let model = model(service)
        defer { model.pause() }
        model.connect()
        XCTAssertTrue(model.busy)
        XCTAssertFalse(model.isConnected)
        model.removeKey()
        try await finish(model)
        XCTAssertEqual(service.deleted, [first.vin])
        XCTAssertEqual(model.garage.vehicles, [second])
        XCTAssertNil(service.connectedVIN)
        XCTAssertFalse(model.isConnected)
    }

    func testFailedLocalKeyDeletionPreservesCarAndSetup() async throws {
        let service = RecordingVehicleService()
        service.connectedValue = false
        service.deleteFailure = .keyUnavailable
        let model = model(service)
        defer { model.pause() }
        model.removeKey()
        try await finish(model)
        XCTAssertEqual(model.garage.vehicles, [first, second])
        XCTAssertEqual(model.profile, first)
        XCTAssertEqual(model.message, VehicleIssue.keyUnavailable.errorDescription)
    }

    func testFailedPairingDoesNotMarkTheCarAuthorized() async throws {
        let service = RecordingVehicleService()
        service.connectedValue = false
        service.pairFailure = .pairingNotApproved
        let car = VehicleProfile(vin: first.vin)
        let model = AppModel(testService: service, testGarage: VehicleGarage(vehicles: [car]))
        defer { model.pause() }
        model.startPairing()
        try await finish(model)
        XCTAssertEqual(model.profile, car)
        XCTAssertEqual(model.screen, .pair)
        XCTAssertFalse(model.isConnected)
        XCTAssertEqual(model.message, VehicleIssue.pairingNotApproved.errorDescription)
    }

    func testCancellingPairingCannotAdvanceSetupAfterwards() async throws {
        let service = RecordingVehicleService()
        service.pairDelay = .milliseconds(100)
        let car = VehicleProfile(vin: first.vin)
        let model = AppModel(testService: service, testGarage: VehicleGarage(vehicles: [car]))
        defer { model.pause() }
        model.startPairing()
        model.backToConnect()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.screen, .connect)
        XCTAssertEqual(model.profile, car)
        XCTAssertFalse(model.busy)
        XCTAssertTrue(service.deleted.isEmpty)
    }

    func testDoorAndShortcutRouteToTheRequestedVIN() async throws {
        let service = RecordingVehicleService()
        let model = model(service)
        defer { model.pause() }
        XCTAssertTrue(model.selectCar(vin: second.vin))
        model.openDoor()
        try await finish(model)
        XCTAssertEqual(service.opened, [second.vin])
        let outcome = try await model.openFromShortcut(vin: first.vin)
        XCTAssertEqual(outcome, .confirmedOpen)
        XCTAssertEqual(service.opened, [second.vin, first.vin])
        XCTAssertEqual(model.profile, first)
        do {
            _ = try await model.openFromShortcut(vin: "5YJ3E1EA0LF000099")
            XCTFail("A removed or unknown car must not fall back to another car")
        } catch VehicleIssue.setupRequired {}
        XCTAssertEqual(service.opened.count, 2)
    }

    func testCarCannotChangeWhilePhysicalRequestIsInFlight() async throws {
        let service = RecordingVehicleService()
        let model = model(service)
        defer { model.pause() }
        model.openDoor()
        XCTAssertFalse(model.selectCar(vin: second.vin))
        model.addCar()
        model.removeKey()
        XCTAssertEqual(model.profile, first)
        XCTAssertTrue(service.deleted.isEmpty)
        XCTAssertEqual(model.screen, .everyday)
        try await finish(model)
        XCTAssertEqual(service.opened, [first.vin])
    }

    func testSwitchingCancelsAConnectionAttemptToThePreviousCar() async throws {
        let service = RecordingVehicleService()
        service.connectionDelay = .milliseconds(100)
        let model = model(service)
        defer { model.pause() }
        model.connect()
        XCTAssertTrue(model.busy)
        XCTAssertTrue(model.selectCar(vin: second.vin))
        model.connect()
        try await finish(model)
        XCTAssertEqual(model.profile, second)
        XCTAssertEqual(service.connectedVIN, second.vin)
        XCTAssertTrue(service.opened.isEmpty)
    }

    func testManagingAnotherCarKeepsTheActiveCar() async throws {
        let service = RecordingVehicleService()
        let model = model(service)
        defer { model.pause() }
        model.connect()
        try await finish(model)
        XCTAssertTrue(model.rename("Atlas II", vin: second.vin))
        XCTAssertEqual(model.profile, first)
        XCTAssertEqual(model.garage.vehicles.last?.name, "Atlas II")
        model.removeKey(vin: second.vin)
        try await finish(model)
        XCTAssertEqual(service.deleted, [second.vin])
        XCTAssertEqual(model.profile, first)
        XCTAssertTrue(model.isConnected)
        XCTAssertEqual(model.garage.vehicles, [first])
    }
}
