# Getting started

[← Documentation](README.md)

## Open and run

1. Open `OpenLatch.xcodeproj` in Xcode with Swift 6.2 or newer. The app targets iOS 17+.
2. Select the OpenLatch scheme and an iPhone simulator. Run to see the real welcome
   screen. To explore all flows without a car, select the **OpenLatch Preview**
   scheme (or add `-demo` in Scheme → Run → Arguments).
3. For a physical iPhone, select your signing team and an available bundle identifier
   in the app target. Build and run on your unlocked phone.
4. Enter or paste the 17-character VIN; keep your existing key card ready. The app
   requests a new driver key, then waits for authorization in the car. Follow the
   car's instructions, place the existing key card on the car's centre-console
   reader, and approve the new key on the car's screen.
5. Test the driver door while parked. Confirm **It worked** only after checking
   the door. Optionally configure Siri/Shortcuts, then use the one-button home screen.

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
