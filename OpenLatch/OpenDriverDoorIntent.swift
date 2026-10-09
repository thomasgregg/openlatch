import AppIntents
import OpenLatchCore

struct OpenDriverDoorIntent: AppIntent {
    static let title: LocalizedStringResource = "Open driver door"
    static let description = IntentDescription("Release your paired Tesla’s driver-door latch over nearby Bluetooth.")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Car")
    var car: OpenLatchCar?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        let available = model.garage.vehicles.filter { $0.paired && $0.tested }.map {
            OpenLatchCar(id: $0.vin, name: model.displayName(for: $0))
        }
        let target: OpenLatchCar
        if let car { target = car }
        else if available.count > 1 {
            target = try await $car.requestDisambiguation(among: available, dialog: "Which car?")
        } else if let only = available.first { target = only }
        else { throw VehicleIssue.setupRequired }
        let outcome = try await model.openFromShortcut(vin: target.id)
        if outcome == .confirmedOpen {
            return .result(dialog: "Your driver door is open.")
        }
        return .result(dialog: "Request accepted. Check your driver door.")
    }
}

struct OpenLatchCar: AppEntity, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Car")
    static let defaultQuery = OpenLatchCarQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(String(id.suffix(6)))")
    }
}

enum OpenLatchDoor: String, AppEnum {
    case defaultDoor, driver, passenger, rearDriver, rearPassenger
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Door")
    static let caseDisplayRepresentations: [OpenLatchDoor: DisplayRepresentation] = [
        .defaultDoor: DisplayRepresentation(title: "Default door", image: .init(systemName: "car.top.door.front.left.and.front.right.open")),
        .driver: DisplayRepresentation(title: "Driver door", image: .init(systemName: "car.top.door.front.left.open")),
        .passenger: DisplayRepresentation(title: "Passenger door", image: .init(systemName: "car.top.door.front.right.open")),
        .rearDriver: DisplayRepresentation(title: "Rear driver-side door", image: .init(systemName: "car.top.door.rear.left.open")),
        .rearPassenger: DisplayRepresentation(title: "Rear passenger-side door", image: .init(systemName: "car.top.door.rear.right.open"))
    ]
    var vehicleDoor: VehicleDoor? {
        switch self {
        case .defaultDoor: nil
        case .driver: .driver
        case .passenger: .passenger
        case .rearDriver: .rearDriver
        case .rearPassenger: .rearPassenger
        }
    }
}

struct OpenDoorIntent: AppIntent {
    static let title: LocalizedStringResource = "Open door"
    static let description = IntentDescription("Open your paired Tesla’s chosen door over nearby Bluetooth.")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Car")
    var car: OpenLatchCar?
    @Parameter(title: "Door", default: .defaultDoor)
    var door: OpenLatchDoor

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$door) on \(\.$car)")
    }

    init() {}
    init(door: OpenLatchDoor) { self.door = door }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        let available = model.garage.vehicles.filter { $0.paired && $0.tested }.map {
            OpenLatchCar(id: $0.vin, name: model.displayName(for: $0))
        }
        let target: OpenLatchCar
        if let car { target = car }
        else if available.count > 1 {
            target = try await $car.requestDisambiguation(among: available, dialog: "Which car?")
        } else if let only = available.first { target = only }
        else { throw VehicleIssue.setupRequired }
        let outcome = try await model.openFromShortcut(vin: target.id, door: door.vehicleDoor)
        if outcome == .confirmedOpen { return .result(dialog: "Door open") }
        return .result(dialog: "Request accepted. Check your door.")
    }
}

struct OpenLatchCarQuery: EntityQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [OpenLatchCar] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    @MainActor func suggestedEntities() async throws -> [OpenLatchCar] {
        let model = AppModel.shared
        return model.garage.vehicles.filter { $0.paired && $0.tested }.map {
            OpenLatchCar(id: $0.vin, name: model.displayName(for: $0))
        }
    }
}

// Separate actions give Siri and the Action Button an unambiguous door target;
// their behavior does not depend on preset parameter values being preserved.
struct OpenPassengerDoorIntent: AppIntent {
    static let title: LocalizedStringResource = "Open passenger door"
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Car") var car: OpenLatchCar?
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try await openNamedDoor(car: car, door: .passenger) {
            try await $car.requestDisambiguation(among: $0, dialog: "Which car?")
        }
    }
}

struct OpenRearDriverDoorIntent: AppIntent {
    static let title: LocalizedStringResource = "Open rear driver-side door"
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Car") var car: OpenLatchCar?
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try await openNamedDoor(car: car, door: .rearDriver) {
            try await $car.requestDisambiguation(among: $0, dialog: "Which car?")
        }
    }
}

struct OpenRearPassengerDoorIntent: AppIntent {
    static let title: LocalizedStringResource = "Open rear passenger-side door"
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Car") var car: OpenLatchCar?
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try await openNamedDoor(car: car, door: .rearPassenger) {
            try await $car.requestDisambiguation(among: $0, dialog: "Which car?")
        }
    }
}

@MainActor private func openNamedDoor(
    car: OpenLatchCar?, door: VehicleDoor,
    chooseCar: ([OpenLatchCar]) async throws -> OpenLatchCar
) async throws -> some IntentResult & ProvidesDialog {
    let model = AppModel.shared
    let available = model.garage.vehicles.filter { $0.paired && $0.tested }.map {
        OpenLatchCar(id: $0.vin, name: model.displayName(for: $0))
    }
    let target: OpenLatchCar
    if let car { target = car }
    else if available.count > 1 { target = try await chooseCar(available) }
    else if let only = available.first { target = only }
    else { throw VehicleIssue.setupRequired }
    let outcome = try await model.openFromShortcut(vin: target.id, door: door)
    if outcome == .confirmedOpen { return .result(dialog: "Door open") }
    return .result(dialog: "Request accepted. Check your door.")
}

struct OpenLatchShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .blue
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenDriverDoorIntent(),
            phrases: ["Open my driver door with \(.applicationName)"],
            shortTitle: "Open driver door",
            systemImageName: "car.top.door.front.left.open"
        )
        AppShortcut(
            intent: OpenDoorIntent(),
            phrases: ["Open my car door with \(.applicationName)"],
            shortTitle: "Open default door",
            systemImageName: "car.top.door.front.left.and.front.right.open"
        )
        AppShortcut(
            intent: OpenPassengerDoorIntent(),
            phrases: ["Open my passenger door with \(.applicationName)"],
            shortTitle: "Open passenger door",
            systemImageName: "car.top.door.front.right.open"
        )
        AppShortcut(
            intent: OpenRearDriverDoorIntent(),
            phrases: ["Open my rear driver-side door with \(.applicationName)"],
            shortTitle: "Open rear driver-side door",
            systemImageName: "car.top.door.rear.left.open"
        )
        AppShortcut(
            intent: OpenRearPassengerDoorIntent(),
            phrases: ["Open my rear passenger-side door with \(.applicationName)"],
            shortTitle: "Open rear passenger-side door",
            systemImageName: "car.top.door.rear.right.open"
        )
    }
}
