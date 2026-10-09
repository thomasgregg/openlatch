import SwiftUI
import AppIntents

struct VINGuide: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Text("Tesla app → scroll to the bottom → copy VIN")
                Text("Or in your car: Controls → Software")
            }
            .navigationTitle("Your VIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct ShortcutGuide: View {
    var onDone: (() -> Void)? = nil

    var body: some View {
        if onDone != nil {
            NavigationStack {
                content.toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone?() }
                } }
            }
        } else { content }
    }

    private var content: some View {
        List {
            Section("Siri") {
                Text("“Open my driver door with OpenLatch”")
                    .textSelection(.enabled)
            }
            Section {
                ShortcutsLink()
            } footer: {
                Text("Near your car. iPhone unlocked.")
            }
            Section("Action Button") {
                Text("Settings → Action Button → Shortcut")
                Text("Choose “Open default door” or a specific door.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
    }
}
