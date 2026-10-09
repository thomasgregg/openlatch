import Foundation
import Security
import OpenLatchCore

/// Both the VIN and onboarding state stay in device-only protected storage.
/// A separate keychain item holds the SDK's private key.
struct ProfileStore {
    private let service: String
    init(service: String = "org.openlatch.profile") { self.service = service }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "vehicle"]
    }

    func load() throws -> VehicleGarage? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        var item: CFTypeRef?
        let result = SecItemCopyMatching(attributes as CFDictionary, &item)
        if result == errSecItemNotFound { return nil }
        guard result == errSecSuccess, let data = item as? Data else {
            throw VehicleIssue.keyUnavailable
        }
        let decoder = JSONDecoder()
        if let garage = try? decoder.decode(VehicleGarage.self, from: data) { return garage }
        // Keep existing single-car installations and their VIN-keyed keys.
        let legacy = try decoder.decode(VehicleProfile.self, from: data)
        return VehicleGarage(vehicles: [legacy], selectedVIN: legacy.vin)
    }

    func save(_ garage: VehicleGarage) throws {
        let values: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(garage),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let result = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if result == errSecItemNotFound {
            var attributes = query
            values.forEach { attributes[$0.key] = $0.value }
            guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
                throw VehicleIssue.keyUnavailable
            }
        } else if result != errSecSuccess { throw VehicleIssue.keyUnavailable }
    }

    func remove() throws {
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else {
            throw VehicleIssue.keyUnavailable
        }
    }
}
