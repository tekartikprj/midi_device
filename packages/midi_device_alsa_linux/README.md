# tekartik_midi_device_alsa_linux

The Linux implementation of [tekartik_midi_device](../midi_device/README.md):
the ALSA raw MIDI devices (`hw:<card>,<device>`: USB keyboards, sound card
MIDI ports) through `tekartik_alsa_midi_linux` (FFI on `libasound.so.2`).
Dart VM and Flutter on Linux.

## Getting started

Not on pub.dev, a git dependency (it brings `tekartik_midi_device`, whose API
it re-exports):

```yaml
dependencies:
  tekartik_midi_device_alsa_linux:
    git:
      url: https://github.com/tekartikprj/midi_device
      path: packages/midi_device_alsa_linux
```

List the devices ([example/main.dart](example/main.dart),
`dart run example/main.dart`):

```dart
import 'dart:io';

import 'package:tekartik_midi_device_alsa_linux/midi_device_alsa_linux.dart';

/// Lists the ALSA MIDI devices.
Future<void> main() async {
  if (!Platform.isLinux) {
    stderr.writeln('ALSA MIDI is Linux only');
    return;
  }
  // Read it once: each access builds a new manager.
  final manager = midiDeviceManagerAlsaLinux;
  var devices = await manager.getDevices();
  if (devices.isEmpty) {
    print('No MIDI device (plug a keyboard)');
  }
  for (var device in devices) {
    print(
      '${device.id} ${device.name} '
      'in: ${device.inputPortCount} out: ${device.outputPortCount}',
    );
  }
}
```

Then connect, send and receive with `connectDevice(id)`, or keep a device
connected with `MidiDeviceService(manager: manager, select: ...)`, as in the
[tekartik_midi_device README](../midi_device/README.md).

## Good to know

* `midiDeviceManagerAlsaLinux` builds a new manager at each access (its own
  connected devices): read it once and reuse it.
* On the web the getter throws `UnsupportedError`; on macOS and Windows
  nothing guards it: check `Platform.isLinux` first.
* `connectDevice()` throws when the device is gone or another program holds
  it. Always `disconnect()`: an open device stays busy for the other
  programs until the process ends.
* `onMessageReceived` gives every message, clock (`0xf8`) and active sensing
  (`0xfe`) included: filter them.
* `midiDeviceManagerAlsaLinuxDebug = true` prints the devices listed and the
  connections.
