import Testing
import Foundation
@testable import OpenLatchCore

@Suite struct VINTests {
    @Test(arguments: [
        ("5YJ3E1EA0LF000000", VehicleModel.model3),
        (" lrw3e7fa0rc000000\n", .model3),
        ("5YJYGDEE0MF000000", .modelY),
        ("7SAYGDEE0SA000000", .modelY),
        ("LRWYGCEE0SC000000", .modelY),
        ("XP7YGCEK0SB000000", .modelY),
        ("5YJSA1E20MF000000", .modelS),
        ("7SASA1E20SF000000", .modelS),
        ("5YJXCBE20MF000000", .modelX),
        ("7SAXCBE20SF000000", .modelX),
        ("7G2CEHED0SA000000", .cybertruck),
        ("7SACEHED0SA000000", .cybertruck)
    ])
    func detectsModelOffline(_ vin: String, _ expected: VehicleModel) {
        #expect(VehicleModel.detected(from: vin) == expected)
    }

    @Test(arguments: ["", "7G2", "5YJ3E1EA0LF00000I", "WVW3E1EA0LF000000", "7G2TEHED0SA000000", "XP73E1EA0LF000000"])
    func unknownVINDoesNotShowTheWrongCar(_ vin: String) {
        #expect(VehicleModel.detected(from: vin) == .unknown)
    }

    @Test func existingProfilesGetArtworkWithoutChangingStorage() throws {
        let legacy = Data(#"{"vin":"7G2CEHED0SA000000","name":"Truck","paired":true,"tested":true,"onboardingComplete":true}"#.utf8)
        let profile = try JSONDecoder().decode(VehicleProfile.self, from: legacy)
        #expect(profile.vehicleModel == .cybertruck)
        #expect(profile.nextScreen == .everyday)
        #expect(profile.defaultDoor == .driver)
        let restored = try JSONDecoder().decode(VehicleProfile.self, from: JSONEncoder().encode(profile))
        #expect(restored == profile)
    }

    @Test func defaultDoorSurvivesGarageStorageAndIsIndependentPerCar() throws {
        var first = VehicleProfile(vin: "5YJ3E1EA0LF000000")
        first.defaultDoor = .rearPassenger
        let second = VehicleProfile(vin: "5YJ3E1EA0LF000001")
        let garage = VehicleGarage(vehicles: [first, second], selectedVIN: first.vin)
        let restored = try JSONDecoder().decode(VehicleGarage.self, from: JSONEncoder().encode(garage))
        #expect(restored.selected?.defaultDoor == .rearPassenger)
        #expect(restored.vehicles.last?.defaultDoor == .driver)
    }

    @Test func normalizesPastedVIN() {
        #expect(VIN.normalized("  lrw3e7fa0rc000000\n") == "LRW3E7FA0RC000000")
        #expect(VIN.isValid("  lrw3e7fa0rc000000\n"))
    }
    @Test(arguments: ["", "123", "5YJ3E1EA0LF00000I", "5YJ3E1EA0LF00000O", "5YJ3E1EA0LF00000Q", "5YJ3E1EA0LF00000é", "5YJ3E1EA0 LF000000"])
    func rejectsInvalidVIN(_ vin: String) { #expect(!VIN.isValid(vin)) }
    @Test func resumesOnlyVerifiedSetup() {
        var profile = VehicleProfile(vin: "5YJ3E1EA0LF000000")
        #expect(profile.nextScreen == .pair)
        profile.paired = true
        #expect(profile.nextScreen == .test)
        profile.tested = true
        #expect(profile.nextScreen == .shortcut)
        profile.onboardingComplete = true
        #expect(profile.nextScreen == .everyday)
    }
}

private actor FakeDoor: DoorTransport {
    var states: [DoorState]
    var sent = 0
    var failure: VehicleIssue?
    var queryFailureAfterSend = false
    var delay: Duration = .zero
    init(_ states: [DoorState], failure: VehicleIssue? = nil, queryFailure: Bool = false, delay: Duration = .zero) {
        self.states = states; self.failure = failure
        queryFailureAfterSend = queryFailure; self.delay = delay
    }
    func doorState() async throws -> DoorState {
        if queryFailureAfterSend && sent > 0 { throw VehicleIssue.statusUnavailable }
        if states.count > 1 { return states.removeFirst() }
        return states.first ?? .unknown
    }
    func sendUnlatch() async throws {
        sent += 1
        if delay != .zero { try await Task.sleep(for: delay) }
        if let failure { throw failure }
    }
    var count: Int { sent }
}

@Suite struct DoorPolicyTests {
    @Test func alreadyOpenDoesNotSend() async throws {
        let door = FakeDoor([.open])
        #expect(try await DoorController().open(using: door) == .confirmedOpen)
        #expect(await door.count == 0)
    }
    @Test func confirmsReportedMovement() async throws {
        let door = FakeDoor([.closed, .open])
        #expect(try await DoorController().open(using: door) == .confirmedOpen)
        #expect(await door.count == 1)
    }
    @Test func acknowledgementIsNotMovement() async throws {
        let door = FakeDoor([.closed])
        #expect(try await DoorController().open(using: door) == .acceptedUnconfirmed)
        #expect(await door.count == 1)
    }
    @Test func lostStatusDoesNotResend() async throws {
        let door = FakeDoor([.closed], queryFailure: true)
        #expect(try await DoorController().open(using: door) == .acceptedUnconfirmed)
        #expect(await door.count == 1)
    }
    @Test func uncertainCommandNeverRetries() async {
        let door = FakeDoor([.closed], failure: .commandUncertain)
        await #expect(throws: VehicleIssue.self) { try await DoorController().open(using: door) }
        #expect(await door.count == 1)
    }
    @Test func simultaneousRequestsAreRejected() async throws {
        let door = FakeDoor([.closed, .open], delay: .milliseconds(250))
        let controller = DoorController()
        let first = Task { try await controller.open(using: door) }
        while await door.count == 0 { await Task.yield() }
        await #expect(throws: VehicleIssue.self) { try await controller.open(using: door) }
        #expect(try await first.value == .confirmedOpen)
        #expect(await door.count == 1)
    }
}

@Suite struct GarageTests {
    @Test func preservesSelectionAndSetupThroughStorage() throws {
        let first = VehicleProfile(vin: "5YJ3E1EA0LF000000", paired: true, tested: true, onboardingComplete: true)
        let pending = VehicleProfile(vin: "5YJ3E1EA0LF000001", paired: true)
        let garage = VehicleGarage(vehicles: [first, pending], selectedVIN: pending.vin)
        let restored = try JSONDecoder().decode(VehicleGarage.self, from: JSONEncoder().encode(garage))
        #expect(restored.selected?.nextScreen == .test)
        #expect(restored.vehicles.first == first)
    }

    @Test func duplicateVINUpdatesOneCarAndRemovalKeepsTheOther() {
        var first = VehicleProfile(vin: "5YJ3E1EA0LF000000")
        let second = VehicleProfile(vin: "5YJ3E1EA0LF000001")
        var garage = VehicleGarage(vehicles: [first, second], selectedVIN: first.vin)
        first.name = "Atlas"
        garage.upsert(first)
        #expect(garage.vehicles.count == 2)
        garage.remove(vin: second.vin)
        #expect(garage.selected == first)
        garage.remove(vin: first.vin)
        #expect(garage.selected == nil)
        #expect(garage.selectedVIN == nil)
    }
}
