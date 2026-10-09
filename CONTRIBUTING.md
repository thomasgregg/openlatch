# Contributing to OpenLatch

Thanks for helping improve a focused, native iPhone app. Start with the [development guide](docs/development.md) and [Bluetooth implementation](docs/bluetooth.md).

## Report an issue

Use [GitHub Issues](https://github.com/thomasgregg/openlatch/issues). Include steps to reproduce, expected and observed behavior, app and iOS versions, and whether you used preview mode or a real vehicle. For vehicle behavior, include the model, model year, firmware and tested door. Redact VINs, keys and personal data from screenshots and logs.

## Submit a change

1. Fork the repository and create a focused branch.
2. Make the change, keeping English and German text in sync.
3. Run the checks relevant to your change from the development guide. For UI changes, check light/dark appearance, larger text and VoiceOver labels.
4. Open a pull request describing the problem, resulting behavior and validation. Include screenshots for visual changes and distinguish simulator checks from physical vehicle evidence.

Protocol changes must preserve explicit vehicle targeting, honest result reporting and the absence of automatic command retries. Update third-party notices when modifying vendored dependencies. Changes to the Xcode project should originate in `project.yml`.

## Validate on a vehicle

Follow the [vehicle validation checklist](docs/vehicle-validation.md). A protocol field or successful preview is not evidence that a door works on a particular vehicle. Report command acceptance separately from observed movement.

Contributions are provided under the project’s [MIT license](LICENSE).
