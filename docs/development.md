# Development

[← Documentation](README.md)

## Build and test

Dependencies are vendored; package resolution does not require internet access.
The checked-in Xcode project is generated from `project.yml`. If changing targets,
install XcodeGen and run `xcodegen generate`.

```sh
swift test
swift test --package-path Packages/TeslaBLE \
  --skip KeychainTeslaKeyStoreTests \
  --skip LoggingTests.testOSLogLoggerPersistsLifecycleAndPublishesTextByDefault
xcodebuild -project OpenLatch.xcodeproj -scheme OpenLatch \
  -destination 'platform=iOS Simulator,name=OpenLatch' test
```

The two exclusions apply to macOS CLI-hosted tests: iOS Keychain behavior is tested
in the app's simulator unit target, and persistent OSLog access requires host
permissions. Run browser/simulator tools outside restrictive process sandboxes.
Simulator unit tests also check cancellation before Bluetooth discovery.
Core tests cover VIN validation, resume state, concurrent requests, pre-open doors,
acknowledgements without movement, lost status, and ambiguous delivery. UI tests use
explicit debug preview mode, including unconfirmed results and key removal.

Debug launch arguments:

- `-demo`: preview transport; never included in release builds.
- `-screen welcome|connect|pair|test|shortcut|everyday`: start a preview screen.
- `-multi-car`: show two sample cars alongside `-demo -screen everyday`.
- `-unconfirmed`, `-uncertain`, `-unavailable`: preview failure states.

## Repository map

| Path | Responsibility |
| --- | --- |
| `OpenLatch/Views/` | SwiftUI onboarding, everyday controls, settings and help |
| `OpenLatch/AppModel.swift` | App state and coordination |
| `OpenLatch/Services/` | Vehicle service and saved car profiles |
| `OpenLatch/OpenDriverDoorIntent.swift` | App Intents, Siri and Shortcuts actions |
| `Sources/OpenLatchCore/` | Shared domain logic and localized core errors |
| `Tests/` | Core package tests |
| `OpenLatchTests/`, `OpenLatchUITests/` | iOS unit and UI coverage |
| `Packages/TeslaBLE/` | Vendored Bluetooth client |
| `Packages/swift-protobuf/` | Vendored protobuf runtime |
| `project.yml` | XcodeGen project definition |
| `scripts/prepare-testflight.sh` | Local signed archive and IPA export |

## Making changes

Keep preview behavior behind Debug launch arguments. Never silently replace failed Bluetooth operations with demo success. Changes to door dispatch must preserve explicit car targeting, selected-door status checks and the absence of automatic retries. Keep English and German String Catalogs in sync when adding user-facing text.

When changing targets or build settings, update `project.yml` and regenerate the Xcode project with `xcodegen generate`. For simulator tests, replace `name=OpenLatch` with an installed simulator name if needed (`xcrun simctl list devices available`).
