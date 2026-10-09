import SwiftUI
import OpenLatchCore

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink("Cars") { CarSettingsListView(model: model) }
                        .accessibilityIdentifier("manageCars")
                    NavigationLink("Shortcuts") { ShortcutGuide() }
                }
                Section {
                    NavigationLink("About") { AboutView() }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { model.settingsPresented = false }
                }
            }
        }
    }
}

private struct CarSettingsListView: View {
    @Bindable var model: AppModel
    var body: some View {
        List {
            Section {
                ForEach(model.garage.vehicles, id: \.vin) { car in
                    NavigationLink {
                        CarSettingsView(model: model, vin: car.vin)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.displayName(for: car))
                            Text(verbatim: String(car.vin.suffix(6)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("manage-\(car.vin)")
                }
            }
            Section {
                Button("Add car", systemImage: "plus") { model.addCar() }
                    .disabled(!model.canChangeCar)
            }
        }
        .navigationTitle("Cars")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { model.settingsPresented = false }
            }
        }
    }
}

private struct CarSettingsView: View {
    @Bindable var model: AppModel
    let vin: String
    @State private var removing = false
    @State private var attemptedRemoval = false

    private var car: VehicleProfile? {
        model.garage.vehicles.first { $0.vin == vin }
    }
    var body: some View {
        Form {
            if let car {
                Section {
                    NavigationLink {
                        RenameView(model: model, vin: vin)
                    } label: {
                        LabeledContent("Car name", value: model.displayName(for: car))
                    }
                    .accessibilityIdentifier("renameCar")
                    Picker("Default door", selection: Binding(
                        get: { model.garage.vehicles.first(where: { $0.vin == vin })?.defaultDoor ?? .driver },
                        set: { model.setDefaultDoor($0, vin: vin) }
                    )) {
                        ForEach(VehicleDoor.allCases, id: \.self) { door in
                            Text(door.title).tag(door)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("defaultDoor")
                    .disabled(!model.canChangeCar)
                    LabeledContent("VIN", value: vin).textSelection(.enabled)
                    if vin != model.profile?.vin || !car.onboardingComplete {
                        Button(car.onboardingComplete ? LocalizedStringKey("Use this car") : LocalizedStringKey("Finish setup")) {
                            model.selectCar(vin: vin)
                        }
                        .disabled(!model.canChangeCar)
                    }
                }
                Section {
                    Button("Remove car", role: .destructive) { removing = true }
                        .disabled(!model.canChangeCar)
                }
                if attemptedRemoval, let message = model.message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle(car.map { model.displayName(for: $0) } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { model.settingsPresented = false }
            }
        }
        .alert("Remove this car?", isPresented: $removing) {
            Button("Remove car", role: .destructive) {
                attemptedRemoval = true
                model.removeKey(vin: vin)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes this car and its key from this iPhone. Also delete OpenLatch in the car: Controls → Locks.")
        }
    }
}

struct CarListView: View {
    @Bindable var model: AppModel
    var didSelect: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(model.garage.vehicles, id: \.vin) { car in
                Button {
                    if model.selectCar(vin: car.vin) {
                        if let didSelect { didSelect() } else { dismiss() }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.displayName(for: car)).foregroundStyle(.primary)
                            Text(verbatim: String(car.vin.suffix(6)))
                                .font(.caption).foregroundStyle(.secondary)
                            if !car.onboardingComplete {
                                Text("Finish setup").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if car.vin == model.profile?.vin {
                            Image(systemName: "checkmark").foregroundStyle(.blue)
                        }
                    }
                }
                .accessibilityIdentifier("car-\(car.vin)")
                .accessibilityAddTraits(car.vin == model.profile?.vin ? [.isSelected] : [])
                .disabled(!model.canChangeCar)
            }
            Button("Add car", systemImage: "plus") { model.addCar() }
                .disabled(!model.canChangeCar)
        }
        .navigationTitle("Cars")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RenameView: View {
    @Bindable var model: AppModel
    let vin: String
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var saveFailed = false
    var body: some View {
        Form {
            TextField("Car name", text: $name)
                .accessibilityIdentifier("carNameInput")
                .submitLabel(.done)
                .onSubmit { save() }
            if saveFailed, let message = model.message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Car name")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button("Save") { save() }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } }
        .onAppear {
            if let car = model.garage.vehicles.first(where: { $0.vin == vin }) {
                name = model.displayName(for: car)
            }
        }
    }
    private func save() {
        if model.rename(name, vin: vin) { dismiss() }
        else { saveFailed = true }
    }
}

private struct AboutView: View {
    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    BrandIcon(size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OpenLatch").font(.headline)
                        Text("Version 0.1.0").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
            }
            Section {
                NavigationLink("Licenses") { LicenseView() }
                NavigationLink("Source libraries") { SourceLibrariesView() }
            } header: {
                Text("Open source · Local Bluetooth")
            } footer: {
                Text("Independent of Tesla.")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LicenseView: View {
    var body: some View {
        List {
            NavigationLink("OpenLatch") {
                LicenseTextView(title: "OpenLatch", resource: "OpenLatchLicense")
            }
            NavigationLink("TeslaBLE") {
                LicenseTextView(title: "TeslaBLE", resource: "TeslaBLELicense")
            }
            NavigationLink("SwiftProtobuf") {
                LicenseTextView(title: "SwiftProtobuf", resource: "SwiftProtobufLicense")
            }
            NavigationLink("Tesla protocol") {
                LicenseTextView(title: String(localized: "Tesla protocol"), resource: "TeslaProtocolLicense")
            }
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SourceLibrariesView: View {
    var body: some View {
        List {
            Link("TeslaBLE", destination: URL(string: "https://github.com/shoujiaxin/swift-tesla-ble")!)
            Link("SwiftProtobuf", destination: URL(string: "https://github.com/apple/swift-protobuf")!)
            Link("Tesla protocol", destination: URL(string: "https://github.com/teslamotors/vehicle-command")!)
        }
        .navigationTitle("Source libraries")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LicenseTextView: View {
    let title: String
    let resource: String
    var body: some View {
        ScrollView {
            Text(licenseText)
                .font(.footnote).textSelection(.enabled).padding(24)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return String(localized: "Licenses unavailable.")
        }
        return text
    }
}
