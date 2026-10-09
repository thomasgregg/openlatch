# OpenLatch Privacy Policy

Effective: 9 October 2026

OpenLatch connects your iPhone directly to your vehicle over Bluetooth. The app
does not require a Tesla account sign-in, operate a command backend, or include
advertising, analytics or tracking SDKs. We do not receive or collect data from
your use of the app.

## Information kept on your iPhone

OpenLatch stores the VINs and names of your added cars, their setup status, your
selected car, each car's default door, and the cryptographic keys needed to
communicate with the car. These records are kept in protected, device-only iOS
Keychain storage. They are not synchronized through iCloud Keychain or sent to
OpenLatch servers.

The app reads connection and door status from your nearby vehicle to carry out
your request and display feedback. Commands and status responses travel over
local Bluetooth between your iPhone and the vehicle. Pairing shares the app's
public key with the vehicle; the private key remains on the iPhone.

Bluetooth access is used to find, pair with and communicate with your car. If
you choose Paste, the app reads the text you paste from the clipboard to fill
the VIN field. It does not send clipboard contents to a server.

## Your controls

You can remove a car and its locally stored key in Settings → Cars. To revoke
the app's vehicle authorization, also remove the corresponding key using the
vehicle's key-management screen. Removing data from the phone does not remove
a key from an offline vehicle. iOS Keychain items can survive app deletion, so
remove the car in the app and revoke its vehicle key before uninstalling if you
want to remove that authorization fully.

## Support and external services

If you voluntarily contact us or submit a GitHub issue, we receive the
information you provide for responding to your request. Please do not submit
private keys, full VINs, location information or other sensitive data in public
issues. GitHub handles its website and accounts under its own privacy policy.
Apple handles App Store, TestFlight and any diagnostics you choose to share
under Apple's policies. These services are separate from the app's local
Bluetooth operation.

Questions about this policy can be submitted through the
[OpenLatch support page](support.md).

## Deutsch

OpenLatch verbindet dein iPhone lokal über Bluetooth mit deinem Auto. Die App
benötigt keine Tesla-Anmeldung und hat weder einen Befehlsserver noch Werbung,
Analyse- oder Tracking-SDKs. Wir erhalten keine Daten aus deiner App-Nutzung.

VINs, Autonamen, Einrichtungsstatus, ausgewähltes Auto, Standardtüren und
Fahrzeugschlüssel werden lokal im geschützten, gerätegebundenen iOS-Schlüsselbund
gespeichert. Die Daten werden nicht über den iCloud-Schlüsselbund synchronisiert
oder an OpenLatch-Server gesendet. Fahrzeugstatus und Türbefehle werden direkt
zwischen iPhone und Auto übertragen. Beim Koppeln erhält das Auto den öffentlichen
Schlüssel; der private Schlüssel bleibt auf dem iPhone. Beim Tippen auf
„Einfügen“ liest die App den eingefügten Text, um das VIN-Feld zu befüllen.

Unter Einstellungen → Autos kannst du ein Auto und seinen lokalen Schlüssel
entfernen. Entferne zusätzlich den zugehörigen Schlüssel im Auto, um dessen
Berechtigung zu widerrufen. Das Löschen am iPhone entfernt keinen Schlüssel
aus einem nicht verbundenen Auto. Schlüsselbund-Einträge können das Deinstallieren
der App überdauern.

Wenn du uns freiwillig kontaktierst oder ein GitHub-Issue erstellst, erhalten wir
die von dir angegebenen Informationen zur Bearbeitung deiner Anfrage. Teile in
öffentlichen Issues keine privaten Schlüssel, vollständigen VINs oder anderen
sensiblen Daten. Für GitHub, den App Store, TestFlight und freiwillig mit Apple
geteilte Diagnosedaten gelten die Datenschutzbestimmungen der jeweiligen Anbieter.

Datenschutzfragen: [OpenLatch-Support](support.md).
