import Foundation
import Observation
import OpenLatchCore
import UIKit

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    var screen: AppScreen = .welcome
    private(set) var garage = VehicleGarage()
    var profile: VehicleProfile? { garage.selected }
    var vinInput = ""
    var busy = false
    var connectionLabel = String(localized: "Disconnected")
    var isConnected = false
    var message: String?
    var testAttempted = false
    var doorOpen = false
    var settingsPresented = false
    var shortcutsPresented = false
    var carsPresented = false
    var storageFailed = false
    let isDemo: Bool

    // Capture release-equivalent UI with fictional simulator data for store artwork.
    var showsPreviewLabel: Bool {
        #if DEBUG
        isDemo && !ProcessInfo.processInfo.arguments.contains("-store-screenshots")
        #else
        false
        #endif
    }

    @ObservationIgnored private let service: any VehicleService
    @ObservationIgnored private let store = ProfileStore()
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var cleanup: Task<Void, Never>?
    @ObservationIgnored private var shortcutOperation: Task<DoorOutcome, Error>?
    @ObservationIgnored private var feedbackReset: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var connectingOnly = false
    @ObservationIgnored private var additionReturnVIN: String?

    init() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        isDemo = args.contains("-demo")
        service = isDemo ? DemoVehicleService() : BluetoothVehicleService()
        if isDemo {
            // Native paste control tests need a deterministic simulator clipboard.
            if args.contains("-empty-clipboard") { UIPasteboard.general.items = [] }
            if let i = args.firstIndex(of: "-clipboard"), args.indices.contains(i + 1) {
                UIPasteboard.general.string = args[i + 1]
            }
            if let index = args.firstIndex(of: "-screen"), args.indices.contains(index + 1),
               let target = AppScreen(rawValue: args[index + 1]) {
                screen = target
                if target != .welcome && target != .connect {
                    let demoVIN: String
                    if let i = args.firstIndex(of: "-vehicle-vin"), args.indices.contains(i + 1), VIN.isValid(args[i + 1]) {
                        demoVIN = args[i + 1]
                    } else { demoVIN = "5YJ3E1EA0LF000000" }
                    garage.upsert(VehicleProfile(vin: demoVIN, paired: target != .pair,
                                             tested: target == .everyday || target == .shortcut,
                                             onboardingComplete: target == .everyday))
                    if args.contains("-multi-car") {
                        garage.upsert(VehicleProfile(vin: "5YJ3E1EA0LF000001", name: "Bluebird", paired: true,
                                                     tested: true, onboardingComplete: true))
                        garage.select(vin: "5YJ3E1EA0LF000000")
                    }
                }
            }
            return
        }
        #else
        isDemo = false
        service = BluetoothVehicleService()
        #endif
        reload()
    }

    #if DEBUG
    init(testService: any VehicleService, testGarage: VehicleGarage) {
        isDemo = true
        service = testService
        garage = testGarage
        screen = profile?.nextScreen ?? .welcome
    }
    #endif

    var carName: String {
        profile.map { displayName(for: $0) } ?? String(localized: "My Tesla")
    }

    var canChangeCar: Bool { !busy || connectingOnly }

    func displayName(for car: VehicleProfile) -> String {
        car.name == "My Tesla" ? String(localized: "My Tesla") : car.name
    }

    func reload() {
        do {
            garage = try store.load() ?? VehicleGarage()
            screen = profile?.nextScreen ?? .welcome
            storageFailed = false
            message = nil
        } catch {
            storageFailed = true
            message = String(localized: "Unlock your iPhone, then try again.")
        }
    }

    private func persist(_ value: VehicleProfile) throws {
        var updated = garage
        updated.upsert(value)
        try persistGarage(updated)
    }

    private func persistGarage(_ value: VehicleGarage) throws {
        if !isDemo { try store.save(value) }
        garage = value
    }

    func addCar() {
        guard canChangeCar, !storageFailed else { return }
        additionReturnVIN = profile?.vin
        pause()
        message = nil
        vinInput = ""
        testAttempted = false
        settingsPresented = false
        carsPresented = false
        screen = .connect
    }

    @discardableResult
    func selectCar(vin: String) -> Bool {
        guard canChangeCar, let target = garage.vehicles.first(where: { $0.vin == vin }) else { return false }
        do {
            var updated = garage
            updated.select(vin: vin)
            try persistGarage(updated)
            pause()
            message = nil
            testAttempted = false
            vinInput = target.vin
            screen = target.nextScreen
            settingsPresented = false
            return true
        } catch {
            message = String(localized: "Couldn’t save your car. Unlock your iPhone and try again.")
            return false
        }
    }

    func leaveSetup() {
        guard canChangeCar else { return }
        let returnVIN = additionReturnVIN ?? garage.vehicles.first(where: { $0.onboardingComplete })?.vin
        additionReturnVIN = nil
        if let returnVIN { selectCar(vin: returnVIN) }
        else { message = nil; screen = .welcome }
    }

    func identify() {
        guard !busy, VIN.isValid(vinInput) else { return }
        let normalized = VIN.normalized(vinInput)
        if garage.vehicles.contains(where: { $0.vin == normalized }) {
            selectCar(vin: normalized)
            return
        }
        do {
            try persist(VehicleProfile(vin: vinInput))
            message = nil
            screen = .pair
        } catch { message = String(localized: "Couldn’t save your car. Unlock your iPhone and try again.") }
    }

    func startPairing() {
        guard !busy, let profile, !profile.paired else { return }
        run {
            self.connectionLabel = String(localized: "Pairing…")
            try await self.service.pair(vin: profile.vin)
            try Task.checkCancellation()
            var updated = profile
            updated.paired = true
            try self.persist(updated)
            self.isConnected = true
            self.connectionLabel = String(localized: "Connected")
            self.screen = .test
        }
    }

    func connect() {
        guard !busy, let profile, profile.paired else { return }
        run(connectionOnly: true) {
            self.connectionLabel = String(localized: "Connecting…")
            try await self.service.connect(vin: profile.vin)
            try Task.checkCancellation()
            self.isConnected = await self.service.connected
            self.connectionLabel = self.isConnected ? String(localized: "Connected") : String(localized: "Disconnected")
        }
    }

    func openDoor(_ door: VehicleDoor? = nil) {
        guard !busy, let profile, profile.paired else { return }
        let targetDoor = door ?? profile.defaultDoor
        feedbackReset?.cancel()
        doorOpen = false
        run {
            let outcome = try await self.service.openDoor(vin: profile.vin, door: targetDoor)
            try Task.checkCancellation()
            self.isConnected = await self.service.connected
            self.connectionLabel = self.isConnected ? String(localized: "Connected") : String(localized: "Disconnected")
            self.testAttempted = true
            self.doorOpen = outcome == .confirmedOpen
            self.message = self.doorOpen ? String(localized: "Door open") : String(localized: "Request accepted. Check your door.")
            self.clearDoorFeedbackLater()
        }
    }

    func confirmTest() {
        guard !busy, testAttempted, var profile else { return }
        do {
            profile.tested = true
            try persist(profile)
            message = nil
            doorOpen = false
            screen = .shortcut
        } catch { message = String(localized: "Couldn’t save your setup. Try again.") }
    }

    func finishOnboarding() {
        guard var profile, profile.paired, profile.tested else { return }
        do {
            profile.onboardingComplete = true
            try persist(profile)
            message = nil
            screen = .everyday
            additionReturnVIN = nil
        } catch { message = String(localized: "Couldn’t save your setup. Try again.") }
    }

    func rename(_ name: String, vin: String? = nil) -> Bool {
        guard var profile = garage.vehicles.first(where: { $0.vin == (vin ?? self.profile?.vin) }) else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        profile.name = String(trimmed.prefix(40))
        do {
            var updated = garage
            updated.upsert(profile)
            if let selected = garage.selectedVIN { updated.select(vin: selected) }
            try persistGarage(updated)
            return true
        }
        catch { message = String(localized: "Couldn’t save the name. Try again."); return false }
    }

    func setDefaultDoor(_ door: VehicleDoor, vin: String) {
        guard canChangeCar, var car = garage.vehicles.first(where: { $0.vin == vin }) else { return }
        car.defaultDoor = door
        do {
            var updated = garage
            updated.upsert(car)
            if let selected = garage.selectedVIN { updated.select(vin: selected) }
            try persistGarage(updated)
        } catch { message = String(localized: "Couldn’t save your preference. Try again.") }
    }

    func removeKey(vin: String? = nil) {
        guard canChangeCar, let profile = garage.vehicles.first(where: { $0.vin == (vin ?? self.profile?.vin) }) else { return }
        // A reconnect can be cancelled; a physical door request must finish first.
        if busy { pause() }
        let removingSelectedCar = profile.vin == self.profile?.vin
        run {
            if removingSelectedCar { await self.service.disconnect() }
            try Task.checkCancellation()
            // Local removal does not revoke the car-side whitelist entry.
            // The destructive confirmation explains the remaining car step.
            try self.service.deleteLocalKey(vin: profile.vin)
            var remaining = self.garage
            remaining.remove(vin: profile.vin)
            try self.persistGarage(remaining)
            self.vinInput = self.profile?.vin ?? ""
            if removingSelectedCar {
                self.testAttempted = false
                self.doorOpen = false
                self.isConnected = false
                self.feedbackReset?.cancel()
                self.connectionLabel = String(localized: "Disconnected")
            }
            self.settingsPresented = false
            self.screen = self.profile?.nextScreen ?? .welcome
            self.additionReturnVIN = nil
        }
    }

    func pause() {
        generation += 1
        let previous = operation
        let shortcut = shortcutOperation
        let pendingCleanup = cleanup
        previous?.cancel()
        shortcut?.cancel()
        feedbackReset?.cancel()
        operation = nil
        shortcutOperation = nil
        busy = false
        connectingOnly = false
        isConnected = false
        connectionLabel = String(localized: "Disconnected")
        doorOpen = false
        cleanup = Task {
            await pendingCleanup?.value
            await previous?.value
            _ = try? await shortcut?.value
            await service.disconnect()
        }
    }

    func backToConnect() {
        pause()
        vinInput = profile?.vin ?? ""
        message = nil
        screen = .connect
    }

    func openFromShortcut(vin: String? = nil, door: VehicleDoor? = .driver) async throws -> DoorOutcome {
        // A foreground reconnect may already be running. Wait for that benign
        // operation; the model's busy flag serializes all physical requests.
        if busy && !connectingOnly { throw VehicleIssue.busy }
        if let operation { await operation.value }
        await cleanup?.value
        try Task.checkCancellation()
        guard !busy else { throw VehicleIssue.busy }
        let target = vin.flatMap { requested in garage.vehicles.first { $0.vin == requested } } ?? (vin == nil ? profile : nil)
        guard let profile = target, profile.paired, profile.tested else { throw VehicleIssue.setupRequired }
        if profile.vin != self.profile?.vin {
            var updated = garage
            updated.select(vin: profile.vin)
            try persistGarage(updated)
            isConnected = false
            connectionLabel = String(localized: "Disconnected")
            screen = profile.nextScreen
        }
        busy = true
        connectingOnly = false
        feedbackReset?.cancel()
        doorOpen = false
        message = nil
        let id = generation
        let targetDoor = door ?? profile.defaultDoor
        let request = Task { try await service.openDoor(vin: profile.vin, door: targetDoor) }
        shortcutOperation = request
        defer {
            if generation == id { busy = false; shortcutOperation = nil }
        }
        let outcome = try await withTaskCancellationHandler {
            try await request.value
        } onCancel: { request.cancel() }
        try Task.checkCancellation()
        guard generation == id else { throw CancellationError() }
        isConnected = await service.connected
        connectionLabel = isConnected ? String(localized: "Connected") : String(localized: "Disconnected")
        doorOpen = outcome == .confirmedOpen
        message = doorOpen ? String(localized: "Door open") : String(localized: "Request accepted. Check your door.")
        clearDoorFeedbackLater()
        return outcome
    }

    private func clearDoorFeedbackLater() {
        feedbackReset?.cancel()
        feedbackReset = Task {
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            // This is command feedback, not a continuously monitored door state.
            doorOpen = false
            if message == String(localized: "Door open") { message = nil }
        }
    }

    func monitorConnection() async {
        while !Task.isCancelled {
            if !busy {
                let connected = await service.connected
                guard !Task.isCancelled else { return }
                isConnected = connected
                connectionLabel = isConnected ? String(localized: "Connected") : String(localized: "Disconnected")
            }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
    }

    private func run(connectionOnly: Bool = false, _ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        connectingOnly = connectionOnly
        message = nil
        let id = generation
        let pendingCleanup = cleanup
        operation = Task {
            do {
                await pendingCleanup?.value
                try Task.checkCancellation()
                try await action()
            }
            catch is CancellationError { }
            catch {
                guard self.generation == id else { return }
                self.isConnected = await self.service.connected
                self.connectionLabel = self.isConnected ? String(localized: "Connected") : String(localized: "Disconnected")
                self.message = (error as? VehicleIssue)?.errorDescription ?? String(localized: "Couldn’t complete the request. Try again.")
                // A possibly delivered test needs physical confirmation, but
                // isn't automatically marked successful.
                if let issue = error as? VehicleIssue, case .commandUncertain = issue {
                    self.testAttempted = true
                }
            }
            guard self.generation == id else { return }
            self.busy = false
            self.operation = nil
        }
    }
}
