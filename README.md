<div align="center">
  <img src="docs/images/icon.png" width="88" alt="OpenLatch app icon">
  <h1>OpenLatch</h1>
  <p><strong>Your Tesla door. One tap away.</strong></p>
  <p>A focused iPhone app for releasing a chosen door over local Bluetooth.<br>Built with SwiftUI. No Tesla login, command backend or analytics.</p>
  <p>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-1683FF?style=flat-square" alt="License: MIT"></a>
    <img src="https://img.shields.io/badge/iOS-17%2B-1683FF?style=flat-square&amp;logo=apple&amp;logoColor=white" alt="iOS 17 or newer">
    <img src="https://img.shields.io/badge/Swift-6.2%2B-F05138?style=flat-square&amp;logo=swift&amp;logoColor=white" alt="Swift 6.2 or newer">
    <img src="https://img.shields.io/badge/status-early%20beta-F5A623?style=flat-square" alt="Status: early beta">
  </p>
  <p><a href="#get-started">Get started</a> · <a href="docs/README.md">Documentation</a> · <a href="CONTRIBUTING.md">Contribute</a> · <a href="https://github.com/thomasgregg/openlatch/issues">Report an issue</a></p>
</div>

---

## A small app for an everyday action

OpenLatch keeps door release close at hand: pick your car, tap the button, and see the result. Pair directly with the vehicle using an existing key card, then use the app, Siri, Shortcuts or a supported iPhone’s Action Button.

- **One tap, your preferred door.** Save a default per car, or choose another door for a single request.
- **Multiple cars, separate keys.** Name your cars and switch between them without repeating setup.
- **Local Bluetooth.** Commands go directly from your iPhone to the nearby vehicle.
- **Native iPhone experience.** Light and dark appearance, Dynamic Type, VoiceOver labels and reduced-motion support.
- **English and German.** Interface, help, permission prompts and Siri phrases are localized.
- **Honest feedback.** A command acknowledgement is distinguished from confirmed door movement; ambiguous requests are never automatically retried.

> **Early beta:** the owner reported successful pairing and driver-door operation. Other doors and device-level shortcut registration still need physical vehicle validation. Support depends on the vehicle and firmware; see the [validation guide](docs/vehicle-validation.md).

## A closer look

<table>
  <tr>
    <td align="center"><img src="docs/images/everyday.png" width="180" alt="Light appearance with a vehicle illustration and the Open driver door button"></td>
    <td align="center"><img src="docs/images/dark-mode.png" width="180" alt="Everyday door control in dark appearance"></td>
    <td align="center"><img src="docs/images/cars.png" width="180" alt="Saved cars in OpenLatch settings"></td>
    <td align="center"><img src="docs/images/pairing.png" width="180" alt="Pairing instructions for the vehicle key-card reader"></td>
  </tr>
  <tr>
    <td align="center"><sub>One-tap control</sub></td>
    <td align="center"><sub>Dark appearance</sub></td>
    <td align="center"><sub>Your cars</sub></td>
    <td align="center"><sub>Guided pairing</sub></td>
  </tr>
</table>

<sub>Simulator preview captures with sample data. Screen details may evolve during the beta.</sub>

## Get started

You’ll need a Mac with Xcode and Swift 6.2+, an iPhone running iOS 17+, a compatible nearby Tesla and its existing key card for pairing. The simulator supports UI previews; real Bluetooth requires a physical iPhone.

```sh
git clone https://github.com/thomasgregg/openlatch.git
cd openlatch
open OpenLatch.xcodeproj
```

1. Choose the **OpenLatch Preview** scheme to explore the app without a car.
2. To use Bluetooth, choose **OpenLatch**, select your signing team and bundle identifier, and run on an unlocked iPhone.
3. Enter the vehicle’s 17-character VIN and follow the car’s key-card authorization instructions.
4. Test the driver door while parked. Confirm **It worked** only after checking the door physically.

See [Getting started](docs/getting-started.md) for car settings, other doors, shortcuts and troubleshooting. Build from source using the steps above; [TestFlight preparation](docs/testflight.md) explains how to prepare your own beta build.

## How it works

```text
iPhone / SwiftUI  →  local Bluetooth  →  signed VCSEC session  →  chosen door
```

OpenLatch uses CoreBluetooth and a vendored TeslaBLE client to establish signed vehicle-security sessions. A door action sends one selected `closureMoveRequest` field set to `OPEN`, then checks the selected door’s status. Door release is a different operation from unlocking the vehicle.

Keys and VINs stay in device-only Keychain storage while unlocked. **The paired key has Tesla’s driver role**, whose authorization is broader than the door controls shown by the app. Removing a car deletes its local key; remove the matching key under the vehicle’s **Controls → Locks** to revoke car-side access too.

Read [Bluetooth and security](docs/bluetooth.md) for the protocol, request lifecycle and key handling.

## For developers

Dependencies are vendored. The Xcode project is generated from `project.yml`; core logic can be tested independently:

```sh
swift test
```

The [development guide](docs/development.md) covers Bluetooth package tests, iOS unit/UI tests, preview launch arguments and the repository layout. Contributions to accessibility, localization, testing and vehicle validation are welcome; start with [CONTRIBUTING.md](CONTRIBUTING.md).

## Documentation

| Guide | Focus |
| --- | --- |
| [Getting started](docs/getting-started.md) | Pairing, everyday use, cars and shortcuts |
| [Development](docs/development.md) | Build, test and contribute |
| [Bluetooth and security](docs/bluetooth.md) | Protocol, privacy and key lifecycle |
| [Vehicle validation](docs/vehicle-validation.md) | Compatibility evidence and physical test checklist |
| [TestFlight preparation](docs/testflight.md) | Archive and beta distribution |

## Credits and license

OpenLatch code is [MIT licensed](LICENSE). Its Bluetooth implementation builds on [swift-tesla-ble](https://github.com/shoujiaxin/swift-tesla-ble), Apple’s SwiftProtobuf runtime and Tesla’s published vehicle protocol. Local patches and dependency licenses are recorded in [Third-party notices](THIRD_PARTY_NOTICES.md); licenses are also available inside the app under **Settings → About → Licenses**.

OpenLatch is an independent project and is not affiliated with Tesla, Inc.
