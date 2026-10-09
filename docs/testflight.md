# TestFlight preparation

[← Documentation](README.md)

## TestFlight preparation

The production OpenLatch scheme archives in Release with real Bluetooth only.
Version/build numbers use MARKETING_VERSION and CURRENT_PROJECT_VERSION; the
initial beta is 0.1.0 (1). The encryption declaration covers the current use of
Apple's OS-provided CryptoKit primitives. Reassess it if crypto dependencies change.

To create a signed archive and export an IPA locally, using your Developer team:

```sh
TEAM_ID=YOURTEAMID BUILD_NUMBER=1 bash scripts/prepare-testflight.sh
```

Artifacts are saved in `work/testflight/0.1.0-1/`. The script never uploads or
invites testers. Increment BUILD_NUMBER for later uploads. English/German beta
descriptions, What to Test text and reviewer notes are in `outputs/testflight/`.

In App Store Connect, use bundle ID `org.openlatch.app`, app name OpenLatch,
primary language English (US), and a unique SKU such as `openlatch-ios`. An app
record and an active Apple Developer Program membership are needed for upload.
Use an existing matching record if one is already registered. Add a real feedback
email and the required contact information; the project does not invent these.
Start with internal TestFlight testing on your own car. External testers require
Apple's beta review and additional app metadata.

Apple references: [upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds),
[encryption documentation](https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption/).
