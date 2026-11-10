# tekartik_midi_device_flutter_command

The Flutter implementation of
[tekartik_midi_device](../midi_device/README.md) on the
[flutter_midi_command](https://pub.dev/packages/flutter_midi_command) plugin:
the USB, virtual and network MIDI devices (BLE MIDI too, see below) of
Android, iOS, macOS, Linux, Windows and the web, behind the portable
`MidiDeviceManager` API (re-exported here).

## Getting started

Not on pub.dev, a git dependency:

```yaml
dependencies:
  tekartik_midi_device_flutter_command:
    git:
      url: https://github.com/tekartikprj/midi_device
      path: packages/midi_device_flutter_command
```

Do the platform setup of flutter_midi_command in the app (Bluetooth
permissions and usage descriptions for BLE MIDI), then:

```dart
import 'dart:typed_data';

import 'package:tekartik_midi_device_flutter_command/midi_device_flutter_command.dart';

/// Read it once: each access of the getter builds a new manager.
final MidiDeviceManager midiManager = midiDeviceManagerFlutterCommand;

/// Plays a middle C on the first device with an output.
Future<void> playMiddleC() async {
  var devices = await midiManager.getDevices();
  var device = devices.firstWhere((device) => device.outputPortCount > 0);
  var connected = await midiManager.connectDevice(device.id);
  try {
    await connected.sendData(Uint8List.fromList([0x90, 60, 100]));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await connected.sendData(Uint8List.fromList([0x80, 60, 0]));
  } finally {
    await connected.disconnect();
  }
}
```

To keep a device connected, give the manager to a `MidiDeviceService`, as in
the [tekartik_midi_device README](../midi_device/README.md).

## Good to know

* `getDevices()` lists what the plugin knows. BLE MIDI devices need the
  flutter_midi_command_ble transport, set once at startup
  (`MidiCommand(bleTransport: UniversalBleMidiTransport())` of
  flutter_midi_command), then a scan (`startBluetooth()`,
  `startScanningForBluetoothDevices()`); without it these calls throw a
  `StateError`.
* `connectDevice(id)` waits for the connection (up to 30 s in
  flutter_midi_command) and throws when the id is unknown or the connection
  fails.
* `onMessageReceived` is filtered on the device and broadcast. `sendData`
  returns at once (no delivery acknowledgment).
* `onDisconnected` completes on `disconnect()` or when the plugin no longer
  lists the device as connected.
* `midiDeviceManagerFlutterCommandDebug = true` prints the devices listed and
  the connections.
* Tests: no fake backend here; write the shared code against
  `MidiDeviceManager` and test it with an in-memory manager.
