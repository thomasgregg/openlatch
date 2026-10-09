import XCTest
import CryptoKit
import TeslaBLE
import OpenLatchCore
import Security
@testable import OpenLatch

final class KeychainTests: XCTestCase {
    func testProfilePersistsUpdatesAndDeletes() throws {
        let store = ProfileStore(service: "org.openlatch.tests.profile.\(UUID())")
        defer { try? store.remove() }
        XCTAssertNil(try store.load())
        var profile = VehicleProfile(vin: "5YJ3E1EA0LF000000")
        try store.save(VehicleGarage(vehicles: [profile]))
        XCTAssertEqual(try store.load()?.selected, profile)
        profile.paired = true
        profile.tested = true
        profile.name = "Test car"
        var garage = VehicleGarage(vehicles: [profile])
        let second = VehicleProfile(vin: "5YJ3E1EA0LF000001", name: "Second car", paired: true)
        garage.upsert(second)
        try store.save(garage)
        XCTAssertEqual(try store.load(), garage)
        garage.remove(vin: second.vin)
        try store.save(garage)
        XCTAssertEqual(try store.load()?.selected, profile)
        try store.remove()
        XCTAssertNil(try store.load())
        XCTAssertNoThrow(try store.remove())
    }

    func testSingleCarStorageMigratesWithoutLosingSetup() throws {
        let service = "org.openlatch.tests.migration.\(UUID())"
        let store = ProfileStore(service: service)
        defer { try? store.remove() }
        let original = VehicleProfile(vin: "5YJ3E1EA0LF000000", name: "Atlas", paired: true,
                                      tested: true, onboardingComplete: true)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "vehicle",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: try JSONEncoder().encode(original)
        ]
        XCTAssertEqual(SecItemAdd(query as CFDictionary, nil), errSecSuccess)
        let migrated = try XCTUnwrap(store.load())
        XCTAssertEqual(migrated.vehicles, [original])
        XCTAssertEqual(migrated.selectedVIN, original.vin)
        try store.save(migrated)
        XCTAssertEqual(try store.load(), migrated)
    }

    func testPrivateKeyPersistsAndDeletesForOnlySelectedVIN() throws {
        let store = KeychainTeslaKeyStore(service: "org.openlatch.tests.key.\(UUID())")
        let vin = "5YJ3E1EA0LF000000"
        defer { try? store.deletePrivateKey(forVIN: vin) }
        XCTAssertNil(try store.loadPrivateKey(forVIN: vin))
        let key = P256.KeyAgreement.PrivateKey()
        try store.savePrivateKey(key, forVIN: vin)
        let restored = try XCTUnwrap(store.loadPrivateKey(forVIN: vin))
        XCTAssertEqual(restored.publicKey.x963Representation, key.publicKey.x963Representation)
        XCTAssertNil(try store.loadPrivateKey(forVIN: "5YJ3E1EA0LF000001"))
        try store.deletePrivateKey(forVIN: vin)
        XCTAssertNil(try store.loadPrivateKey(forVIN: vin))
    }
}
