import CoreBluetooth
import Foundation

/// Internal CoreBluetooth wrapper that scans for, connects to, and exchanges
/// framed messages with a Tesla vehicle's GATT service. Owns the CBCentralManager
/// lifecycle and the `disconnected → scanning → connecting → connected` state
/// machine. BLE-layer failures surface as `BLEError`; the Dispatcher maps those
/// onto the public `TeslaBLEError` cases (e.g. `.notConnected`, `.timeout`,
/// `.disconnected`). Not public.
@preconcurrency
final class BLETransport: NSObject, Sendable {
    enum ConnectionState {
        case disconnected
        case scanning
        case connecting
        case connected
    }

    nonisolated(unsafe) static let vehicleServiceUUID = CBUUID(string: "00000211-b2d1-43f0-9b88-960cebf8b91e")
    nonisolated(unsafe) static let toVehicleUUID = CBUUID(string: "00000212-b2d1-43f0-9b88-960cebf8b91e")
    nonisolated(unsafe) static let fromVehicleUUID = CBUUID(string: "00000213-b2d1-43f0-9b88-960cebf8b91e")
    private static let maxMessageSize = 1024
    private static let rxTimeout: TimeInterval = 1.0

    // All mutable BLE state is confined to this serial queue. CoreBluetooth
    // delegate callbacks are also delivered on this queue via CBCentralManager.
    private let queue = DispatchQueue(label: "TeslaBLE.BLETransport", qos: .userInitiated)
    private let log: Log
    private nonisolated(unsafe) var centralManager: CBCentralManager!
    private nonisolated(unsafe) var peripheral: CBPeripheral?
    private nonisolated(unsafe) var txCharacteristic: CBCharacteristic?
    private nonisolated(unsafe) var rxCharacteristic: CBCharacteristic?
    private nonisolated(unsafe) var mtu: Int = 20
    private nonisolated(unsafe) var writeType: CBCharacteristicWriteType = .withResponse
    private nonisolated(unsafe) var targetLocalName: String?
    /// Set by `disconnect()`. A transport is single-use, so this never
    /// resets; it separates requested teardown from link loss in the logs.
    private nonisolated(unsafe) var disconnectRequested = false

    private nonisolated(unsafe) var inputBuffer = Data()
    private nonisolated(unsafe) var lastRxTime: Date?

    private nonisolated(unsafe) var connectionContinuation: CheckedContinuation<Void, Error>?
    private nonisolated(unsafe) var connectAbort: Error?
    private nonisolated(unsafe) var receiveContinuations: [CheckedContinuation<Data, Error>] = []

    private(set) nonisolated(unsafe) var state: ConnectionState = .disconnected
    nonisolated(unsafe) var onStateChange: (@Sendable (ConnectionState) -> Void)?

    init(logger: (any TeslaBLELogger)? = nil) {
        log = Log(logger, category: .transport)
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: queue)
    }

    /// Scans for and connects to the vehicle with the given VIN.
    /// Times out after `timeout` seconds if vehicle is not found.
    func connect(vin: String, timeout: TimeInterval = 30) async throws {
        try Task.checkCancellation()
        targetLocalName = VINHelper.bleLocalName(for: vin)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    self.queue.async { [self] in
                        if let connectAbort {
                            continuation.resume(throwing: connectAbort)
                            return
                        }
                        connectionContinuation = continuation
                        if centralManager.state == .poweredOn {
                            startScanning()
                        } else {
                            updateState(.scanning)
                            log.info("waiting for bluetooth: state=\(centralManager.state)")
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw BLEError.timeout
            }
            // First to finish wins; cancel the other
            do {
                try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                // Clean up scanning state
                self.queue.async { [self] in
                    // The cancelled timer can win before the other child has
                    // installed its continuation. Remember the terminal error
                    // so both queue orderings complete instead of hanging.
                    connectAbort = error
                    // `state` tells whether the vehicle was never found
                    // (scanning) or the GATT setup stalled (connecting).
                    if disconnectRequested {
                        log.info("connect abandoned: state=\(state) error=\(error)")
                    } else {
                        log.warning("connect aborted: state=\(state) error=\(error)")
                    }
                    centralManager.stopScan()
                    if let cont = connectionContinuation {
                        connectionContinuation = nil
                        cont.resume(throwing: error)
                    }
                    updateState(.disconnected)
                }
                throw error
            }
        }
    }

    private func startScanning() {
        updateState(.scanning)
        log.info("scan started")
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false],
        )
    }

    /// Sends a protobuf-serialized RoutableMessage.
    func send(_ data: Data) throws {
        guard let peripheral, let txCharacteristic else {
            throw BLEError.notConnected
        }
        let framed = MessageFramer.encode(data)
        guard framed.count <= Self.maxMessageSize + 2 else {
            throw BLEError.messageTooLarge
        }
        let chunks = MessageFramer.fragment(framed, mtu: mtu)
        log.debug("tx: bytes=\(framed.count) chunks=\(chunks.count)")
        for chunk in chunks {
            peripheral.writeValue(chunk, for: txCharacteristic, type: writeType)
        }
    }

    /// Waits for the next complete message from the vehicle.
    func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                // Check if we already have a complete message buffered
                if let message = tryFlush() {
                    continuation.resume(returning: message)
                } else {
                    receiveContinuations.append(continuation)
                }
            }
        }
    }

    func disconnect() {
        queue.async { [self] in
            disconnectRequested = true
            connectAbort = BLEError.disconnected
            log.info("disconnect requested: state=\(state)")
            centralManager.stopScan()
            connectionContinuation?.resume(throwing: BLEError.disconnected)
            connectionContinuation = nil
            if let peripheral {
                centralManager.cancelPeripheralConnection(peripheral)
            }
            cleanup()
        }
    }

    private func cleanup() {
        peripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        inputBuffer = Data()
        updateState(.disconnected)
    }

    private func updateState(_ newState: ConnectionState) {
        state = newState
        onStateChange?(newState)
    }

    private func assertOnTransportQueue() {
        dispatchPrecondition(condition: .onQueue(queue))
    }

    private func tryFlush() -> Data? {
        guard inputBuffer.count >= 2 else { return nil }
        if let (message, consumed) = try? MessageFramer.decode(inputBuffer), let message {
            inputBuffer.removeFirst(consumed)
            return message
        }
        return nil
    }
}

// MARK: - CBCentralManagerDelegate

extension BLETransport: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        assertOnTransportQueue()
        if central.state == .poweredOn {
            log.info("bluetooth state: \(central.state)")
            // If we're waiting to connect, start scanning now
            if connectionContinuation != nil, state != .connecting, state != .connected {
                startScanning()
            }
        } else {
            log.warning("bluetooth state: \(central.state) transport=\(state)")
            connectionContinuation?.resume(throwing: BLEError.bluetoothUnavailable)
            connectionContinuation = nil
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber,
    ) {
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        assertOnTransportQueue()
        let isTarget = localName == targetLocalName
        log.debug("advertisement: match=\(isTarget) rssi=\(RSSI.intValue)")
        guard isTarget else { return }
        log.info("vehicle found: rssi=\(RSSI.intValue)")
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        updateState(.connecting)
        central.connect(peripheral, options: nil)
    }

    nonisolated func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        assertOnTransportQueue()
        log.info("peripheral connected")
        peripheral.discoverServices([Self.vehicleServiceUUID])
    }

    nonisolated func centralManager(
        _: CBCentralManager,
        didFailToConnect _: CBPeripheral,
        error: Error?,
    ) {
        assertOnTransportQueue()
        log.warning("peripheral connect failed: error=\(error)")
        connectionContinuation?.resume(throwing: error ?? BLEError.connectionFailed)
        connectionContinuation = nil
        cleanup()
    }

    nonisolated func centralManager(
        _: CBCentralManager,
        didDisconnectPeripheral _: CBPeripheral,
        error: Error?,
    ) {
        assertOnTransportQueue()
        if !disconnectRequested {
            log.warning("peripheral disconnected unexpectedly: error=\(error) pendingReceives=\(receiveContinuations.count)")
        } else {
            log.info("peripheral disconnected")
        }
        cleanup()
        // Fail any pending receives
        for cont in receiveContinuations {
            cont.resume(throwing: BLEError.disconnected)
        }
        receiveContinuations.removeAll()
    }
}

// MARK: - CBPeripheralDelegate

extension BLETransport: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        assertOnTransportQueue()
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.vehicleServiceUUID }) else {
            log.warning("service discovery failed: error=\(error)")
            connectionContinuation?.resume(throwing: BLEError.serviceNotFound)
            connectionContinuation = nil
            return
        }
        peripheral.discoverCharacteristics(
            [Self.toVehicleUUID, Self.fromVehicleUUID],
            for: service,
        )
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?,
    ) {
        assertOnTransportQueue()
        guard let characteristics = service.characteristics else {
            log.warning("characteristic discovery failed: error=\(error)")
            connectionContinuation?.resume(throwing: BLEError.characteristicsNotFound)
            connectionContinuation = nil
            return
        }
        for char in characteristics {
            if char.uuid == Self.toVehicleUUID {
                txCharacteristic = char
            } else if char.uuid == Self.fromVehicleUUID {
                rxCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
            }
        }
        // Use writeWithResponse if the characteristic doesn't support writeWithoutResponse.
        // Tesla vehicles typically advertise property 0x8 (write with response only).
        if let tx = txCharacteristic, tx.properties.contains(.writeWithoutResponse) {
            writeType = .withoutResponse
            mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
        } else {
            writeType = .withResponse
            mtu = peripheral.maximumWriteValueLength(for: .withResponse)
        }
        log.info("gatt ready: tx=\(txCharacteristic != nil) rx=\(rxCharacteristic != nil) mtu=\(mtu) writeType=\(writeType)")
        updateState(.connected)
        connectionContinuation?.resume()
        connectionContinuation = nil
    }

    nonisolated func peripheral(
        _: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?,
    ) {
        assertOnTransportQueue()
        guard characteristic.uuid == Self.fromVehicleUUID else { return }
        if let error {
            log.warning("rx notification error: error=\(error)")
        }
        guard let value = characteristic.value else { return }

        let now = Date()
        if let lastRx = lastRxTime, now.timeIntervalSince(lastRx) > Self.rxTimeout {
            if !inputBuffer.isEmpty {
                log.warning("rx buffer reset: dropped=\(inputBuffer.count) bytes after gap")
            }
            inputBuffer = Data()
        }
        lastRxTime = now
        inputBuffer.append(value)

        // Deliver complete messages to waiting receivers.
        // Only extract when someone is waiting — otherwise leave in inputBuffer
        // so the next receive() call picks it up via tryFlush().
        while !receiveContinuations.isEmpty, let message = tryFlush() {
            log.debug("rx: bytes=\(message.count)")
            let continuation = receiveContinuations.removeFirst()
            continuation.resume(returning: message)
        }
    }

    nonisolated func peripheral(
        _: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?,
    ) {
        assertOnTransportQueue()
        guard characteristic.uuid == Self.fromVehicleUUID else { return }
        // Without notifications no response can arrive; every request would
        // silently time out.
        if let error {
            log.warning("rx subscribe failed: error=\(error)")
        } else {
            log.info("rx subscribed: notifying=\(characteristic.isNotifying)")
        }
    }

    nonisolated func peripheral(
        _: CBPeripheral,
        didWriteValueFor _: CBCharacteristic,
        error: Error?,
    ) {
        assertOnTransportQueue()
        if let error {
            log.warning("tx write failed: error=\(error)")
        }
    }
}

enum BLEError: Error {
    case bluetoothUnavailable
    case notConnected
    case connectionFailed
    case disconnected
    case serviceNotFound
    case characteristicsNotFound
    case messageTooLarge
    case timeout
}
