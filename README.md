<div align="center">
  <img src="docs/images/icon.png" width="88" alt="OpenLatch app icon">
  <h1>OpenLatch</h1>
  <p><strong>Your Tesla door. One tap, one shortcut, or one Siri request away.</strong></p>
  <p>A focused iPhone app for releasing a chosen door over local Bluetooth.<br>Pair with your existing key card. No Tesla login or API setup.<br>No command server or analytics.</p>
  <p>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-1683FF?style=flat-square" alt="License: MIT"></a>
    <img src="https://img.shields.io/badge/iOS-17%2B-1683FF?style=flat-square&amp;logo=apple&amp;logoColor=white" alt="iOS 17 or newer">
    <img src="https://img.shields.io/badge/Siri%20%26%20Shortcuts-App%20Intents-1683FF?style=flat-square" alt="Siri and Shortcuts via App Intents">
  </p>
  <p><a href="#get-started">Get started</a> · <a href="docs/README.md">Documentation</a> · <a href="CONTRIBUTING.md">Contribute</a> · <a href="https://github.com/thomasgregg/openlatch/issues">Report an issue</a></p>
</div>

---

## A closer look

<table>
  <tr>
    <td align="center"><img src="docs/images/connect.png" width="180" alt="Enter your VIN to connect your car"></td>
    <td align="center"><img src="docs/images/pairing.png" width="180" alt="Authorize OpenLatch with your existing key card"></td>
    <td align="center"><img src="docs/images/shortcuts.png" width="180" alt="Set up Siri, Shortcuts and the Action Button"></td>
    <td align="center"><img src="docs/images/everyday.png" width="180" alt="Current daily control screen with default door and Other doors"></td>
  </tr>
  <tr>
    <td align="center"><sub>1 · Connect your car</sub></td>
    <td align="center"><sub>2 · Pair your key</sub></td>
    <td align="center"><sub>3 · Optional shortcuts</sub></td>
    <td align="center"><sub>4 · Daily use</sub></td>
  </tr>
</table>

<sub>App screenshots captured in simulator preview mode with sample cars.</sub>

## Contents

- [A closer look](#a-closer-look)
- [Why OpenLatch?](#why-openlatch)
- [Get started](#get-started)
- [Features](#features)
- [Siri, Shortcuts and the Action Button](#siri-shortcuts-and-the-action-button)
- [Privacy and connection](#privacy-and-connection)
- [For developers](#for-developers)
- [Documentation](#documentation)
- [Credits and license](#credits-and-license)

## Why OpenLatch?

Unlocking your Tesla leaves the door latched: you still need to operate the exterior handle. Sometimes you want to release the latch directly—when a handle is awkward to use, when helping a passenger get in, or when you want a familiar voice command or button to do the job.

Tesla’s app includes an **Unlatch Door** quick control for the **driver door**, as described in [Tesla’s owner’s manual](https://www.tesla.com/ownersmanual/model3/en_co/GUID-F907200E-A619-4A95-A0CF-94E0D03BEBEF.html). OpenLatch builds the experience around **choosing the door you want**: driver, front passenger, rear driver-side or rear passenger-side, with a saved default for each car and dedicated Siri and Shortcuts actions.

Choose the passenger door for someone getting in, keep the driver door as your everyday default, or assign a specific car and door to your iPhone’s Action Button. Commands travel directly over nearby Bluetooth, with no Tesla login or command server.

## Get started

### Install OpenLatch

The first App Store release has been submitted and is awaiting Apple’s review. Once it is available, install OpenLatch on your iPhone. You do not need a Mac or Xcode to use the App Store app. Developers can [build from source](#for-developers) now.

### Have these ready

- An **iPhone running iOS 17 or later** with Bluetooth enabled.
- A **compatible Tesla**, parked nearby. Available door functions depend on the car’s hardware and software.
- An **existing authorized Tesla key card** to approve pairing.
- Your car’s **17-character VIN**, which you can find in the Tesla app or on the car’s **Controls → Software** screen.

**No Tesla account sign-in. No Tesla developer account, API keys or access tokens to obtain. No server to set up.** Door commands travel directly over nearby Bluetooth, without an internet connection.

### Pair and open your first door

1. **Open OpenLatch near your parked car.** Keep your iPhone unlocked and allow Bluetooth access when prompted.
2. **Enter or paste the VIN.** Keep your key card ready for the next step.
3. **Authorize OpenLatch in the car.** Follow the app and vehicle prompts, place your existing key card on the vehicle’s key-card reader, and approve the new key on the car’s screen.
4. **Complete the guided door test.** Check the door physically and tap **It worked** only after it releases successfully.
5. **Choose your everyday door.** In **Settings → Cars**, select your car and choose its **Default door**. The main button now uses that door.

Siri, Shortcuts and the Action Button are optional. You can start with the app’s main button and [set up shortcuts](#siri-shortcuts-and-the-action-button) later.

### Everyday use

Stand near your car with your iPhone unlocked, open OpenLatch and tap the main button to release your default door. Tap **Other doors** to choose another door for that request. Releasing the latch does not guarantee that the door swings open automatically.

To add another car, go to **Settings → Cars** and pair it with its own key card. Use the car selector on the main screen to switch between saved cars.

If the car is not found, check the VIN, Bluetooth permission and proximity. If pairing stalls, check the vehicle’s authorization prompt and try the existing key card again. If a request is accepted but door movement is not confirmed, check the door before sending another request.

See the [setup guide](docs/getting-started.md) for more help, switching phones and removing access.

## Features

Pair directly with the vehicle using an existing key card, then use the app, Siri, Shortcuts or a supported iPhone’s Action Button.

- **Simple key-card setup.** Guided pairing with your existing key card; no Tesla login or API access setup.
- **One tap, your preferred door.** Save a default per car, or choose another door for a single request.
- **Siri voice control.** Ask Siri to open your default door or a specific door with OpenLatch.
- **Apple Shortcuts.** Choose the car and door, then add OpenLatch actions to your own shortcuts.
- **Action Button.** Assign an OpenLatch shortcut to the Action Button on supported iPhones.
- **Multiple cars, separate keys.** Name your cars and switch between them without repeating setup.
- **Local Bluetooth.** Commands go directly from your iPhone to the nearby vehicle.
- **Native iPhone experience.** Light and dark appearance, Dynamic Type, VoiceOver labels and reduced-motion support.
- **English and German.** Interface, help, permission prompts and Siri phrases are localized.
- **Honest feedback.** A command acknowledgement is distinguished from confirmed door movement; ambiguous requests are never automatically retried.


## Siri, Shortcuts and the Action Button

Choose one of these actions in Apple Shortcuts:

| Action | Door selection |
| --- | --- |
| **Open default door** | Uses the chosen car’s saved default; the generic **Open door** action also lets you edit the Door parameter |
| **Open driver door** | Driver door |
| **Open passenger door** | Front passenger door |
| **Open rear driver-side door** | Rear door on the driver’s side |
| **Open rear passenger-side door** | Rear door on the passenger’s side |

**With Siri:** say “Open my driver door with OpenLatch” or “Open my car door with OpenLatch” for your saved default. Each named-door action also has its own Siri phrase. With multiple configured cars, Siri asks which car to use unless your shortcut specifies one.

**With Shortcuts:** create a shortcut, add an OpenLatch action, and choose its **Car** and **Door** where available. Named-door actions keep their door selection; the default action follows the car’s saved preference.

**With the Action Button:** save your OpenLatch shortcut, then select it under **Settings → Action Button → Shortcut** on a supported iPhone.

Actions open OpenLatch and use device authentication. Commands connect to the nearby car over Bluetooth. See the [setup guide](docs/getting-started.md) for details.

## Privacy and connection

OpenLatch pairs as a vehicle key and sends commands directly from your iPhone to your nearby car. Keys and VINs stay in device-only Keychain storage. Each car has its own key.

To remove access, remove the car in OpenLatch, then delete the matching key under **Controls → Locks** on the vehicle. Deleting the app alone does not revoke the vehicle’s authorization.

Read [Bluetooth and security](docs/bluetooth.md) for technical details.

## For developers

Building from source requires a Mac with Xcode and Swift 6.2 or newer. Real Bluetooth requires a physical iPhone; the simulator can preview the interface.

```sh
git clone https://github.com/thomasgregg/openlatch.git
cd openlatch
open OpenLatch.xcodeproj
```

Choose **OpenLatch Preview** to explore without a car. To use your car, choose **OpenLatch**, select your signing team and bundle identifier, and run on your iPhone. Then follow the [pairing steps above](#pair-and-open-your-first-door).

The app uses SwiftUI, CoreBluetooth and a vendored TeslaBLE client for signed vehicle-security sessions. A door action sends the selected `closureMoveRequest` field set to `OPEN`, then checks that door’s status.

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
| [TestFlight preparation](docs/testflight.md) | Archive and TestFlight distribution |

## Credits and license

OpenLatch code is [MIT licensed](LICENSE). Its Bluetooth implementation builds on [swift-tesla-ble](https://github.com/shoujiaxin/swift-tesla-ble), Apple’s SwiftProtobuf runtime and Tesla’s published vehicle protocol. Local patches and dependency licenses are recorded in [Third-party notices](THIRD_PARTY_NOTICES.md); licenses are also available inside the app under **Settings → About → Licenses**.

OpenLatch is an independent project and is not affiliated with Tesla, Inc.
