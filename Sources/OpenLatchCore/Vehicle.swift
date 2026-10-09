import Foundation

public enum VIN {
    public static func normalized(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Validate the international VIN character set. Do not impose a North
    /// American checksum on European vehicles or restrict factory prefixes.
    public static func isValid(_ input: String) -> Bool {
        let value = normalized(input)
        return value.utf8.count == 17 && value.utf8.allSatisfy {
            (48...57).contains($0) || ((65...90).contains($0) && ![73, 79, 81].contains($0))
        }
    }
}

/// Offline model-family detection. No Tesla account or network lookup is needed.
public enum VehicleModel: String, Codable, CaseIterable, Sendable {
    case model3, modelY, modelS, modelX, cybertruck, unknown

    public var displayName: String {
        switch self {
        case .model3: "Model 3"
        case .modelY: "Model Y"
        case .modelS: "Model S"
        case .modelX: "Model X"
        case .cybertruck: "Cybertruck"
        case .unknown: ""
        }
    }

    public static func detected(from input: String) -> Self {
        let vin = VIN.normalized(input)
        guard VIN.isValid(vin) else { return .unknown }
        let prefix = String(vin.prefix(3))
        let series = vin[vin.index(vin.startIndex, offsetBy: 3)]
        switch (prefix, series) {
        case ("5YJ", "3"), ("LRW", "3"): return .model3
        case ("5YJ", "Y"), ("7SA", "Y"), ("LRW", "Y"), ("XP7", "Y"): return .modelY
        case ("5YJ", "S"), ("7SA", "S"): return .modelS
        case ("5YJ", "X"), ("7SA", "X"): return .modelX
        case ("7G2", "C"), ("5YJ", "C"), ("7SA", "C"): return .cybertruck
        default: return .unknown
        }
    }
}

public enum VehicleDoor: String, Codable, CaseIterable, Sendable {
    case driver, passenger, rearDriver, rearPassenger
}

public struct VehicleProfile: Codable, Equatable, Sendable {
    public var vin: String
    public var name: String
    public var paired: Bool
    public var tested: Bool
    public var onboardingComplete: Bool
    // Optional storage preserves compatibility with profiles saved before door selection.
    private var preferredDoor: VehicleDoor?
    public var defaultDoor: VehicleDoor {
        get { preferredDoor ?? .driver }
        set { preferredDoor = newValue }
    }
    // Computed from the existing VIN, so stored profiles need no migration.
    public var vehicleModel: VehicleModel { .detected(from: vin) }

    public init(vin: String, name: String = "My Tesla", paired: Bool = false,
                tested: Bool = false, onboardingComplete: Bool = false,
                defaultDoor: VehicleDoor = .driver) {
        self.vin = VIN.normalized(vin)
        self.name = name
        self.paired = paired
        self.tested = tested
        self.onboardingComplete = onboardingComplete
        self.preferredDoor = defaultDoor == .driver ? nil : defaultDoor
    }

    public var nextScreen: AppScreen {
        if !paired { return .pair }
        if !tested { return .test }
        return onboardingComplete ? .everyday : .shortcut
    }
}

/// Device-local cars and the explicitly selected command target.
public struct VehicleGarage: Codable, Equatable, Sendable {
    public private(set) var vehicles: [VehicleProfile]
    public private(set) var selectedVIN: String?

    public init(vehicles: [VehicleProfile] = [], selectedVIN: String? = nil) {
        self.vehicles = []
        self.selectedVIN = nil
        for vehicle in vehicles { upsert(vehicle) }
        if let selectedVIN { select(vin: selectedVIN) }
    }

    public var selected: VehicleProfile? {
        vehicles.first { $0.vin == selectedVIN } ?? vehicles.first
    }

    public mutating func upsert(_ vehicle: VehicleProfile) {
        if let index = vehicles.firstIndex(where: { $0.vin == vehicle.vin }) {
            vehicles[index] = vehicle
        } else { vehicles.append(vehicle) }
        selectedVIN = vehicle.vin
    }

    public mutating func select(vin: String) {
        let vin = VIN.normalized(vin)
        guard vehicles.contains(where: { $0.vin == vin }) else { return }
        selectedVIN = vin
    }

    public mutating func remove(vin: String) {
        vehicles.removeAll { $0.vin == vin }
        if selectedVIN == vin { selectedVIN = vehicles.first?.vin }
    }
}

public enum AppScreen: String, Sendable {
    case welcome, connect, pair, test, shortcut, everyday
}

public enum DoorState: Equatable, Sendable {
    case closed, open, unknown
}

public enum DoorOutcome: Equatable, Sendable {
    case confirmedOpen, acceptedUnconfirmed
}

public enum VehicleIssue: Error, LocalizedError, Sendable {
    case bluetoothUnavailable, notFound, pairingNotApproved, keyUnavailable
    case rejected, statusUnavailable, commandUncertain, busy, setupRequired

    public var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable: String(localized: "Turn on Bluetooth and allow access in Settings.", bundle: .module)
        case .notFound: String(localized: "Move closer to your car, then try again.", bundle: .module)
        case .pairingNotApproved: String(localized: "Pairing wasn’t confirmed. Place your keycard on the car’s centre-console reader and confirm on the car’s screen.", bundle: .module)
        case .keyUnavailable: String(localized: "Unlock your iPhone to access your car key.", bundle: .module)
        case .rejected: String(localized: "The car declined the request. Check that it’s parked and supports this action.", bundle: .module)
        case .statusUnavailable: String(localized: "Couldn’t check the door. Try reconnecting.", bundle: .module)
        case .commandUncertain: String(localized: "Check your door before trying again. The request may have reached the car.", bundle: .module)
        case .busy: String(localized: "A request is already in progress.", bundle: .module)
        case .setupRequired: String(localized: "Finish pairing and testing your door in OpenLatch first.", bundle: .module)
        }
    }
}

/// Testable command policy shared by the app and its Siri action.
/// Never resend a physical action automatically after an ambiguous result.
public protocol DoorTransport: Sendable {
    func doorState() async throws -> DoorState
    func sendUnlatch() async throws
}

public actor DoorController {
    private var inFlight = false
    public init() {}

    public func open(using transport: any DoorTransport) async throws -> DoorOutcome {
        guard !inFlight else { throw VehicleIssue.busy }
        inFlight = true
        defer { inFlight = false }
        try Task.checkCancellation()
        if try await transport.doorState() == .open { return .confirmedOpen }
        try Task.checkCancellation()
        // Exactly one action. A timeout never triggers a retry.
        try await transport.sendUnlatch()
        for attempt in 0..<4 {
            do {
                if try await transport.doorState() == .open { return .confirmedOpen }
            } catch is CancellationError { throw CancellationError() }
            catch { return .acceptedUnconfirmed }
            if attempt < 3 { try await Task.sleep(for: .milliseconds(400)) }
        }
        return .acceptedUnconfirmed
    }
}
