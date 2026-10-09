# Vehicle validation

[← Documentation](README.md)


## First vehicle validation

Use your own parked compatible car, with an existing key card available:

- Verify VIN discovery, pairing approval, key listing, and signed reconnect.
- Check that denial or a dismissed car prompt never completes setup.
- Verify the driver-door release and reported state; confirm other doors stay closed.
- Repeat for each additional door supported by the car. A protocol field does not
  guarantee support on every model or firmware version.
- Check an already-open door, out-of-range connection, Bluetooth permission denial,
  lock/unlock, app backgrounding, and loss of connection during a request.
- Check Siri and Action Button behavior on a physical iPhone.
- Delete the local key and the car-side entry; verify access is revoked.

No model/firmware compatibility matrix is claimed until these checks are performed.

## Reporting results

Include the model, model year, vehicle firmware, iOS version, app version, tested door and observed result. Distinguish a command acknowledgement from physical door movement. Redact full VINs, private keys and personal information from public reports.
