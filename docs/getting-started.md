# Getting started

[← Documentation](README.md)

## Before you start

You need an iPhone running iOS 17 or later, a compatible nearby Tesla, the car’s 17-character VIN, and an existing authorized Tesla key card. Park the car and enable Bluetooth on your iPhone. No Tesla login, developer account, API keys, access tokens or server configuration are needed.

The first App Store release is awaiting Apple’s review. Once available, install the app on your iPhone. For a source build or simulator preview, follow the [development guide](development.md) and the repository’s [build instructions](../README.md#for-developers).

## Pair your car

1. Open OpenLatch near your parked car with your iPhone unlocked. Allow Bluetooth access when prompted.
2. Enter or paste the 17-character VIN. Find it in the Tesla app or on the car’s **Controls → Software** screen.
3. Keep your existing key card ready. Follow the vehicle’s authorization prompts, place the card on the vehicle’s key-card reader and approve the new key on the car’s screen.
4. Complete the guided driver-door test. Check the door physically and confirm **It worked** only after it releases successfully.
5. Choose your preferred **Default door** under **Settings → Cars**. Siri and Shortcuts setup is optional; you can use the main app button straight away.

Use OpenLatch near your car with your iPhone unlocked. The main button releases your default door; **Other doors** lets you select another door for a single request. Door availability depends on vehicle hardware and software. Releasing a latch does not guarantee the door swings open automatically.

The onboarded key has Tesla's **driver** role. Its vehicle authorization is broader
than the door actions exposed by OpenLatch.
The key and VIN stay in device-only Keychain storage while unlocked. Removing the
key in the app deletes it locally; also remove its entry in **Controls → Locks** in
vehicle settings to revoke the car-side authorization. Reinstalling an app may
preserve its Keychain items. A new phone requires pairing again.

## Screens

Welcome → VIN → key pairing → door test → optional shortcuts → everyday.
Settings contains Cars, Shortcuts and About. Under Cars, select a car to edit
its **Car name**, choose its **Default door**, view its full VIN, use it, or remove it.
The main button opens that car's default door. **Other doors** performs a one-off
request without changing the default. The driver door is the initial default;
existing saved cars migrate with that default. Car lists show the final six VIN
characters as a compact disambiguator; this is an OpenLatch design choice.
Add car also lives there. The
name is saved locally in OpenLatch. With multiple cars, the car button on the everyday screen
opens a native picker. Each VIN has its own key and setup state; switching cars
disconnects the previous connection. Existing single-car storage migrates in place.
An interrupted additional setup stays in the picker as **Finish setup**.
Native navigation, forms, sheets and controls support dark mode, Dynamic Type,
VoiceOver labels, and reduced motion. English and German are supported from the
start; the app uses the iPhone’s preferred supported language, with English as the
fallback. Translations live in Apple String Catalogs, including Siri phrases and
the Bluetooth permission prompt. Core errors use localized package resources. The everyday screen has no shortcut promotion.

Shortcuts exposes five actions with door icons: default, driver, passenger,
rear driver-side and rear passenger-side. Named-door shortcuts always target their
named door; the default action follows the target car's saved preference. Existing
driver-door shortcuts retain their original behavior. The generic **Open door**
action also exposes an editable **Door** parameter. All actions open the
app and require device authentication. Add an action using the Shortcuts
app; choose that shortcut in Settings → Action Button → Shortcut on supported phones.
Each action has an optional **Car** parameter. With multiple configured cars, Siri
asks which one to use unless the shortcut specifies a car. Unknown or removed VINs
never fall back to another car.
This MVP disconnects when backgrounded rather than keeping a passive phone key active.

## Troubleshooting

| What you see | What to do |
| --- | --- |
| Bluetooth unavailable in the simulator | Use **OpenLatch Preview** for UI exploration, or a physical iPhone for Bluetooth. |
| Car not found | Check the VIN, Bluetooth permission and proximity to the car. |
| Pairing does not complete | Follow the car’s authorization prompt with an existing key card. A dismissed or denied prompt does not authorize the key. |
| Request accepted, but no confirmed movement | Check the door physically before sending another request. |
| A removed car appears in an old shortcut | Edit the shortcut’s Car parameter; removed VINs never fall back to a different car. |
| Moving to another iPhone | Pair the new phone with the car again. |

## Removing access

Remove the car in OpenLatch to delete its locally stored key. Then remove the matching key in the car’s **Controls → Locks** settings to revoke vehicle authorization. Deleting or reinstalling the app alone is not a reliable revocation method because Keychain items may survive reinstalling.
