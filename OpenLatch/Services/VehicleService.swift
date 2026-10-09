import Foundation
import CryptoKit
import TeslaBLE
import OpenLatchCore

@MainActor
protocol VehicleService: AnyObject {
    var connected: Bool { get async }
    func pair(vin: String) async throws
    func connect(vin: String) async throws
    func openDoor(vin: String, door: VehicleDoor) async throws -> DoorOutcome
    func disconnect() async
    func deleteLocalKey(vin: String) throws
}

@MainActor
final class BluetoothVehicleService: VehicleService {
    private let keys = KeychainTeslaKeyStore(service: "org.openlatch.vehicle-key")
    private let doorController = DoorController()
    private var client: TeslaVehicleClient?

    var connected: Bool {
        get async { await client?.state == .connected }
    }

    func pair(vin: String) async throws {
        // Reuse an existing key if enrollment was interrupted. Never silently
        // replace a key which the vehicle may already have authorized.
        let key: P256.KeyAgreement.PrivateKey
        if let stored = try keys.loadPrivateKey(forVIN: vin) {
            key = stored
            // Setup can be interrupted after approval. Authenticate the saved
            // key first instead of asking the car to enroll it again.
            do { try await connect(vin: vin); return }
            catch is CancellationError { throw CancellationError() }
            catch { await disconnect() }
        }
        else {
            key = KeyPairFactory.generateKeyPair()
            try keys.savePrivateKey(key, forVIN: vin)
        }
        await disconnect()
        let pairingClient = TeslaVehicleClient(vin: vin, keyStore: keys)
        client = pairingClient
        do {
            try await pairingClient.connect(mode: .pairing, timeout: .seconds(12))
            try Task.checkCancellation()
            try await pairingClient.send(.security(.addKey(
                publicKey: KeyPairFactory.publicKeyBytes(of: key),
                role: .driver, formFactor: .iosDevice
            )))
            // Enrollment transmission isn't proof of authorization. Give the
            // owner time, then verify with an authenticated VCSEC handshake.
            try await Task.sleep(for: .seconds(3))
            await pairingClient.disconnect()
            let deadline = ContinuousClock.now.advanced(by: .seconds(100))
            while ContinuousClock.now < deadline {
                try Task.checkCancellation()
                let verifier = TeslaVehicleClient(vin: vin, keyStore: keys)
                client = verifier
                do {
                    try await verifier.connect(mode: .securityOnly, timeout: .seconds(8))
                    try Task.checkCancellation()
                    return
                } catch is CancellationError { throw CancellationError() }
                catch {
                    await verifier.disconnect()
                    try await Task.sleep(for: .seconds(2))
                }
            }
            throw VehicleIssue.pairingNotApproved
        } catch {
            await disconnect()
            try Task.checkCancellation()
            throw Self.friendly(error)
        }
    }

    func connect(vin: String) async throws {
        if let client, await client.vin == vin, await client.state == .connected { return }
        guard try keys.loadPrivateKey(forVIN: vin) != nil else { throw VehicleIssue.setupRequired }
        await disconnect()
        let connection = TeslaVehicleClient(vin: vin, keyStore: keys)
        client = connection
        do {
            try await connection.connect(mode: .securityOnly, timeout: .seconds(12))
            try Task.checkCancellation()
        } catch {
            await disconnect()
            try Task.checkCancellation()
            throw Self.friendly(error)
        }
    }

    func openDoor(vin: String, door: VehicleDoor) async throws -> DoorOutcome {
        try await connect(vin: vin)
        guard let client else { throw VehicleIssue.notFound }
        return try await doorController.open(using: TeslaDoorTransport(client: client, door: door))
    }

    func disconnect() async {
        let old = client
        client = nil
        await old?.disconnect()
    }

    func deleteLocalKey(vin: String) throws { try keys.deletePrivateKey(forVIN: vin) }

    static func friendly(_ error: Error) -> VehicleIssue {
        if let issue = error as? VehicleIssue { return issue }
        guard let error = error as? TeslaBLEError else { return .notFound }
        switch error {
        case .bluetoothUnavailable: return .bluetoothUnavailable
        case .keychain: return .keyUnavailable
        case .commandRejected: return .rejected
        case .commandTimeout: return .commandUncertain
        case .handshakeFailed, .addKeyFailed: return .pairingNotApproved
        default: return .notFound
        }
    }
}

private struct TeslaDoorTransport: DoorTransport {
    let client: TeslaVehicleClient
    let door: VehicleDoor

    func doorState() async throws -> DoorState {
        do {
            guard case .bodyControllerState(let status) = try await client.query(
                .bodyControllerState, timeout: .seconds(3)
            ), status.hasClosureStatuses else { return .unknown }
            let closure: VCSEC_ClosureState_E
            switch door {
            case .driver: closure = status.closureStatuses.frontDriverDoor
            case .passenger: closure = status.closureStatuses.frontPassengerDoor
            case .rearDriver: closure = status.closureStatuses.rearDriverDoor
            case .rearPassenger: closure = status.closureStatuses.rearPassengerDoor
            }
            switch closure {
            case .closurestateOpen, .closurestateAjar: return .open
            case .closurestateClosed: return .closed
            default: return .unknown
            }
        } catch is CancellationError { throw CancellationError() }
        catch { throw VehicleIssue.statusUnavailable }
    }

    func sendUnlatch() async throws {
        try Task.checkCancellation()
        do {
            let command: Command.Security
            switch door {
            case .driver: command = .unlatchDriverDoor
            case .passenger: command = .unlatchPassengerDoor
            case .rearDriver: command = .unlatchRearDriverDoor
            case .rearPassenger: command = .unlatchRearPassengerDoor
            }
            try await client.send(.security(command), timeout: .seconds(5))
        } catch let error as TeslaBLEError {
            if case .commandRejected = error { throw VehicleIssue.rejected }
            // Once dispatch starts, any transport failure is potentially an
            // executed action whose acknowledgement didn't arrive. Don't retry.
            throw VehicleIssue.commandUncertain
        } catch { throw VehicleIssue.commandUncertain }
    }
}

#if DEBUG
/// Explicit preview mode only. Never used as a fallback for real Bluetooth.
@MainActor
final class DemoVehicleService: VehicleService {
    private var isConnected = false
    var connected: Bool { get async { isConnected } }
    func pair(vin: String) async throws {
        let delay: Duration = ProcessInfo.processInfo.arguments.contains("-slow-pair") ? .seconds(30) : .milliseconds(900)
        try await Task.sleep(for: delay)
        isConnected = true
    }
    func connect(vin: String) async throws {
        let delay: Duration = ProcessInfo.processInfo.arguments.contains("-slow-connect") ? .seconds(30) : .milliseconds(250)
        try await Task.sleep(for: delay)
        if ProcessInfo.processInfo.arguments.contains("-unavailable") { throw VehicleIssue.notFound }
        isConnected = true
    }
    func openDoor(vin: String, door: VehicleDoor) async throws -> DoorOutcome {
        try await connect(vin: vin)
        let delay: Duration = ProcessInfo.processInfo.arguments.contains("-slow-door") ? .seconds(3) : .milliseconds(500)
        try await Task.sleep(for: delay)
        if ProcessInfo.processInfo.arguments.contains("-uncertain") { throw VehicleIssue.commandUncertain }
        return ProcessInfo.processInfo.arguments.contains("-unconfirmed") ? .acceptedUnconfirmed : .confirmedOpen
    }
    func disconnect() async { isConnected = false }
    func deleteLocalKey(vin: String) throws {}
}
#endif
