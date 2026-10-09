import SwiftUI
import OpenLatchCore

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: AppModel
    @State private var vinGuidePresented = false
    @State private var canPaste = false
    @FocusState private var vinFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                switch model.screen {
                case .welcome: welcome
                case .connect: connect
                case .pair: pair
                case .test: test
                case .shortcut: shortcut
                case .everyday: everyday
                }
            }
            .toolbar {
                if model.screen == .connect || model.screen == .pair || model.screen == .test {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back", systemImage: "chevron.left") {
                            if model.screen == .pair || model.screen == .test { model.backToConnect() }
                            else { model.leaveSetup() }
                        }.disabled(model.busy)
                    }
                }
                if model.showsPreviewLabel {
                    ToolbarItem(placement: .principal) {
                        Text("Preview").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $vinGuidePresented) { VINGuide() }
        .sheet(isPresented: $model.settingsPresented) { SettingsView(model: model) }
        .sheet(isPresented: $model.carsPresented) {
            NavigationStack {
                CarListView(model: model) { model.carsPresented = false }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { model.carsPresented = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $model.shortcutsPresented) {
            ShortcutGuide {
                model.shortcutsPresented = false
                if model.screen == .shortcut { model.finishOnboarding() }
            }
        }
    }

    private var welcome: some View {
        FlowLayout {
            Spacer(minLength: 40)
            BrandIcon()
            VStack(spacing: 10) {
                Text("OpenLatch").font(.largeTitle.bold())
                Text("One tap. Door open.").foregroundStyle(.secondary)
            }
            Spacer(minLength: 50)
            InlineFeedback(text: model.message)
            if model.storageFailed {
                PrimaryButton(title: "Try again") { model.reload() }
            } else {
                PrimaryButton(title: "Connect car") { model.screen = .connect }
            }
            Text("Have your key card ready.").font(.footnote).foregroundStyle(.secondary)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var connect: some View {
        FlowLayout {
            CarIllustration(model: .detected(from: model.vinInput))
                .frame(height: 210)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 10) {
                Text("VIN").font(.caption).foregroundStyle(.secondary)
                TextField("Vehicle VIN", text: $model.vinInput,
                          prompt: Text("Paste your VIN").foregroundStyle(Color(uiColor: .secondaryLabel)))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.continue)
                    .focused($vinFocused)
                    .onSubmit { model.identify() }
                    .accessibilityLabel("Vehicle VIN")
                    .accessibilityIdentifier("vinInput")
                    .padding(12)
                    .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            Button("Paste", systemImage: "doc.on.clipboard") {
                if let value = UIPasteboard.general.string { model.vinInput = VIN.normalized(value) }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .frame(minHeight: 44)
            .accessibilityLabel("Paste VIN")
            .accessibilityIdentifier("pasteVIN")
            .opacity(canPaste ? 1 : 0)
            .accessibilityHidden(!canPaste)
            Button("Where’s my VIN?") { vinGuidePresented = true }.font(.subheadline)
            Spacer(minLength: 12)
            // Keep validation space when recognition replaces the placeholder,
            // including while the keyboard leaves little room for the spacer.
            Text("Enter a 17-character VIN.")
                .font(.footnote).foregroundStyle(.secondary)
                .opacity(!model.vinInput.isEmpty && !VIN.isValid(model.vinInput) ? 1 : 0)
                .accessibilityHidden(model.vinInput.isEmpty || VIN.isValid(model.vinInput))
            InlineFeedback(text: model.message)
            PrimaryButton(title: "Continue", enabled: VIN.isValid(model.vinInput)) {
                vinFocused = false
                model.identify()
            }
        }
        .navigationTitle("Connect car")
        .scrollDismissesKeyboard(.interactively)
        .onAppear { canPaste = UIPasteboard.general.hasStrings }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            canPaste = UIPasteboard.general.hasStrings
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { canPaste = UIPasteboard.general.hasStrings }
        }
    }

    private var pair: some View {
        FlowLayout {
            Spacer(minLength: 30)
            KeyCardIllustration()
            VStack(spacing: 10) {
                Text("Place your keycard on the car’s centre-console reader.")
                Text("Confirm on the car’s screen.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            Spacer(minLength: 28)
            if model.busy {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Waiting…").foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
            }
            InlineFeedback(text: model.message)
            if !model.busy {
                PrimaryButton(title: "Try pairing again") { model.startPairing() }
            }
            Spacer(minLength: 20)
            Button("Cancel") { model.backToConnect() }.frame(minHeight: 44)
        }
        .navigationTitle("Pair your key")
        .task { model.startPairing() }
    }

    private var test: some View {
        FlowLayout {
            Spacer(minLength: 20)
            CarIllustration(model: model.profile?.vehicleModel ?? .unknown)
            Text("Tap, then pull the door open.")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 30)
            DoorFeedback(text: model.message, success: model.doorOpen)
            PrimaryButton(title: "Test door", busy: model.busy) { model.openDoor(.driver) }
            Button("It worked") { model.confirmTest() }
                .disabled(!model.testAttempted || model.busy)
                .frame(minHeight: 44)
        }
        .navigationTitle("Try your door")
        .sensoryFeedback(.success, trigger: model.doorOpen) { _, opened in opened }
    }

    private var shortcut: some View {
        FlowLayout {
            Spacer(minLength: 30)
            Text("Make it quicker").font(.largeTitle.bold())
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 76, weight: .light))
                .foregroundStyle(.blue.gradient).padding(24)
                .accessibilityHidden(true)
            Text("Use Siri or your Action Button.")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 30)
            InlineFeedback(text: model.message)
            PrimaryButton(title: "Set up Shortcut") { model.shortcutsPresented = true }
            Button("Not now") { model.finishOnboarding() }.frame(minHeight: 44)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var everyday: some View {
        FlowLayout(alignment: .top) {
            HStack(spacing: 8) {
                Image(systemName: model.isConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(model.isConnected ? Color.blue : .secondary)
                Text(model.connectionLabel).foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            CarIllustration(model: model.profile?.vehicleModel ?? .unknown, maximumWidth: 354)
                .frame(height: 266)
                .padding(.top, 32)
            DoorFeedback(text: model.message, success: model.doorOpen)
                .padding(.top, 20)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                PrimaryButton(title: (model.profile?.defaultDoor ?? .driver).openTitle,
                              symbol: (model.profile?.defaultDoor ?? .driver).symbolName, busy: model.busy) {
                    model.openDoor()
                }
                Menu {
                    ForEach(VehicleDoor.allCases.filter { $0 != (model.profile?.defaultDoor ?? .driver) }, id: \.self) { door in
                        Button { model.openDoor(door) } label: {
                            Label(door.openTitle, systemImage: door.symbolName)
                        }
                    }
                } label: {
                    Label("Other doors", systemImage: "chevron.down")
                        .font(.subheadline)
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("otherDoors")
                .disabled(model.busy)
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemBackground))
        }
        .navigationTitle(model.carName)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if model.garage.vehicles.count > 1 {
                    Button("Cars", systemImage: "car.side") { model.carsPresented = true }
                        .labelStyle(.iconOnly)
                        .disabled(!model.canChangeCar)
                }
                Button("Settings", systemImage: "gearshape") { model.settingsPresented = true }
                    .labelStyle(.iconOnly)
            }
        }
        .task(id: model.profile?.vin) {
            model.connect()
            await model.monitorConnection()
        }
        .sensoryFeedback(.success, trigger: model.doorOpen) { _, opened in opened }
    }
}
