# tekartik_midi_device

Platform independent MIDI device interfaces: list the devices, connect to
one, send raw MIDI bytes, receive messages, know when it is unplugged; plus
`MidiDeviceService`, which keeps the device you select connected.

Pure Dart, no platform code: a `MidiDeviceManager` comes from an
implementation package of the same repository:

| Platform | Package | Manager |
|---|---|---|
| Linux (Dart VM, Flutter) | `tekartik_midi_device_alsa_linux` (`packages/midi_device_alsa_linux`) | `midiDeviceManagerAlsaLinux` |
| Flutter (Android, iOS, macOS...) | `tekartik_midi_device_flutter_command` (`packages/midi_device_flutter_command`) | `midiDeviceManagerFlutterCommand` |

Write the shared code against this package and take a `MidiDeviceManager`
as a parameter; tests use an in-memory manager.

## Getting started

Not on pub.dev, git dependencies (this package and an implementation):

```yaml
dependencies:
  tekartik_midi_device:
    git:
      url: https://github.com/tekartikprj/midi_device
      path: packages/midi_device
  tekartik_midi_device_alsa_linux:
    git:
      url: https://github.com/tekartikprj/midi_device
      path: packages/midi_device_alsa_linux
```

Play a note on the first device with an output, print what it sends:

```dart
import 'dart:typed_data';

import 'package:tekartik_midi_device/midi_device.dart';

Future<void> playNote(MidiDeviceManager manager) async {
  var devices = await manager.getDevices();
  var device = devices.firstWhere((device) => device.outputPortCount > 0);
  var connected = await manager.connectDevice(device.id);
  var subscription = connected.onMessageReceived.listen((message) {
    print('${connected.name}: ${message.data}');
  });
  try {
    // Note on, middle C, then note off.
    await connected.sendData(Uint8List.fromList([0x90, 60, 100]));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await connected.sendData(Uint8List.fromList([0x80, 60, 0]));
  } finally {
    await subscription.cancel();
    await connected.disconnect();
  }
}
```

Call it with `midiDeviceManagerAlsaLinux` (import
`package:tekartik_midi_device_alsa_linux/midi_device_alsa_linux.dart`).
[example/main.dart](example/main.dart) runs it and the service on an
in-memory device.

## What to use

| Need | Use |
|---|---|
| List the devices | `manager.getDevices()`: `MidiDevice` (`id`, `name`, `inputPortCount`, `outputPortCount`), a description only |
| Talk to one | `manager.connectDevice(id)`: `ConnectedMidiDevice` (`sendData`, `onMessageReceived`, `onDisconnected`, `disconnect`) |
| Keep a device connected | `MidiDeviceService(manager:, select:)`, `start()`, `stop()`; `onDevice` (null when none), `onMessage` |

## Good to know

- `sendData` takes raw MIDI bytes, status byte first; this package does not
  build nor parse messages.
- `MidiDeviceService` polls `getDevices()` every 5 seconds while nothing is
  connected and connects the first device that `select` accepts. When it is
  unplugged, the next matching device of that list is tried, then the scan
  goes on. `stop()` disconnects it, and nothing is connected after a
  `stop()`, even one called while the devices are being listed.
- `service.onDevice` is a `ValueStream` (rxdart): read `valueOrNull`
  (`value` throws before the first scan ended).
- One service holds one connection; to use several devices, connect them
  with the manager.
- Always `disconnect()` what you connected yourself; `onDisconnected`
  completes when the device goes away.
