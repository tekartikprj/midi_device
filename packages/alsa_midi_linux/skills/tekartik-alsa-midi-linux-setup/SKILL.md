---
name: tekartik-alsa-midi-linux-setup
description: >-
  Use when talking to ALSA raw MIDI hardware on Linux from Dart with
  tekartik_alsa_midi_linux: AlsaMidiDevice.getDevices(), connect(), send(),
  disconnect(), receivedMessages, onDeviceDisconnected, hardwareId, cardId /
  deviceId / inputPorts / outputPorts / toDictionary, the MidiMessage class,
  the package:tekartik_alsa_midi_linux/midi.dart import, the libasound.so.2
  FFI binding (alsa, ALSA generated bindings, ffigen) and its Linux only,
  isolate based receive loop.
---

# ALSA raw MIDI over FFI (tekartik_alsa_midi_linux)

`tekartik_alsa_midi_linux` is a thin `dart:ffi` binding to the ALSA raw MIDI
API (`libasound.so.2`): enumerate sound cards, open a device, write bytes, and
receive parsed MIDI messages from a background isolate. It is Linux only and
has no relation to the higher level `MidiDeviceManager` abstraction; use
`tekartik_midi_device_alsa_linux` when you want that portable API.

## Guidelines

* Dependency (git only, not published on pub.dev):
  ```yaml
  dependencies:
    tekartik_alsa_midi_linux:
      git:
        url: https://github.com/tekartikprj/midi_device
        path: packages/alsa_midi_linux
  ```
* Import `package:tekartik_alsa_midi_linux/midi.dart`: it exports
  `AlsaMidiDevice` (from `alsa_midi_device.dart`) and `MidiMessage` (from
  `midi_message.dart`). The raw generated bindings live in
  `package:tekartik_alsa_midi_linux/alsa_generated_bindings.dart` and are only
  needed for ALSA calls the wrapper does not expose.
* Linux only, and `libasound.so.2` must be installed (`libasound2`/
  `libasound2t64` package). The top level `alsa` binding is created lazily with
  `DynamicLibrary.open`, so importing on another platform is harmless, but the
  first `AlsaMidiDevice` call throws. Guard with `Platform.isLinux` and use
  `@TestOn('vm')` plus a `Platform.isLinux` early return in tests.
* `AlsaMidiDevice.getDevices()` is a static, synchronous scan of every sound
  card: it returns one `AlsaMidiDevice` per raw MIDI device, reusing the live
  instance for devices that are currently connected. Never cache the list, call
  it again after a plug/unplug.
* A device is identified by `AlsaMidiDevice.hardwareId(cardId, deviceId)`
  (`'hw:<card>,<device>'`). `name` is the sound *card* short name, so several
  devices of the same card share it; `inputPorts` and `outputPorts` list the
  subdevices, `type` is always `'native'`, and `toDictionary` gives
  `{name, id, type, connected}` for logs.
* `connect()` is async and returns `false` (it does not throw) when the device
  cannot be opened, for example when another process already owns it. Check the
  result; `connected` then reflects the state. It opens the device in
  non-blocking mode and spawns a receive isolate.
* `send(Uint8List)` is synchronous and fire and forget: status byte first, e.g.
  `[0x90, 60, 127]` note on, `[0xb0, 0x7f, 0]` control change, a full
  `0xf0 ... 0xf7` block for sysex. Errors are only printed, nothing is thrown.
* `receivedMessages` is a broadcast `Stream<MidiMessage>` of complete messages
  (the isolate reassembles running messages and sysex up to `0xf7`). The stream
  controller is shared by all devices of one `getDevices()` scan, so filter on
  `message.device` when several devices are connected. `MidiMessage` exposes
  `data` (`Uint8List`), `timestamp` (local `millisecondsSinceEpoch` at
  reception, not an ALSA clock) and `device`, plus `toDictionary`.
* Clock messages (`0xf8`) and active sensing (`0xfe`) arrive continuously on
  many devices; filter them out before logging.
* `disconnect()` is synchronous: it kills the receive isolate, drains and
  closes both ports and emits the device on the static
  `AlsaMidiDevice.onDeviceDisconnected` broadcast stream. Always call it,
  including on `ProcessSignal.sigint`, otherwise the isolate keeps polling and
  the ALSA device stays busy for other applications.
* Keep only the devices you need connected: each connection runs a busy read
  loop in its own isolate.
* `MidiMessage` here is a different, concrete class from the abstract
  `MidiMessage` of `tekartik_midi_device`; do not import both libraries
  unprefixed in the same file.
* Do not edit `lib/alsa_generated_bindings.dart` by hand, it is produced by
  `dart run ffigen` from the `ffigen:` section of `pubspec.yaml` and needs the
  ALSA headers (`libasound2-dev`) installed.

## Examples

### List devices and send a control change

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:tekartik_alsa_midi_linux/midi.dart';

Future<void> main() async {
  if (!Platform.isLinux) {
    return;
  }
  var devices = AlsaMidiDevice.getDevices();
  for (var device in devices) {
    print('${AlsaMidiDevice.hardwareId(device.cardId, device.deviceId)} '
        '${device.toDictionary} in: ${device.inputPorts} '
        'out: ${device.outputPorts}');
  }
  if (devices.isEmpty) {
    print('no midi device found');
    return;
  }
  var device = devices.first;
  if (!await device.connect()) {
    print('cannot connect to ${device.name}');
    return;
  }
  try {
    device.send(Uint8List.fromList([0xb0, 0x7f, 0]));
  } finally {
    device.disconnect();
  }
}
```

### Receive messages until ctrl-C

```dart
import 'dart:io';

import 'package:tekartik_alsa_midi_linux/midi.dart';

Future<void> main() async {
  var devices = AlsaMidiDevice.getDevices();
  var device = devices.firstWhere((device) => device.inputPorts.isNotEmpty);
  if (!await device.connect()) {
    return;
  }
  ProcessSignal.sigint.watch().listen((_) {
    device.disconnect();
    exit(0);
  });
  await for (var message in device.receivedMessages) {
    if (message.device.deviceId != device.deviceId) {
      continue; // another device of the same scan
    }
    var data = message.data;
    if (data.first == 0xf8 || data.first == 0xfe) {
      continue; // clock / active sensing
    }
    print('${message.timestamp}: $data');
  }
}
```

### Send a sysex request and await the answer

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:tekartik_alsa_midi_linux/midi.dart';

Future<Uint8List?> sysexRequest(
  AlsaMidiDevice device,
  List<int> request, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (!device.connected && !await device.connect()) {
    return null;
  }
  var answerFuture = device.receivedMessages
      .firstWhere((message) => message.data.first == 0xf0)
      .timeout(timeout, onTimeout: () => throw TimeoutException('no sysex'));
  device.send(Uint8List.fromList(request));
  try {
    return (await answerFuture).data;
  } on TimeoutException catch (_) {
    return null;
  }
}
```

### Connect/disconnect test, skipped off Linux

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:tekartik_alsa_midi_linux/midi.dart';
import 'package:test/test.dart';

void main() {
  test('connect/disconnect', () async {
    if (!Platform.isLinux) {
      return;
    }
    for (var device in AlsaMidiDevice.getDevices()) {
      if (await device.connect().timeout(const Duration(seconds: 5))) {
        var id = AlsaMidiDevice.hardwareId(device.cardId, device.deviceId);
        var disconnected = AlsaMidiDevice.onDeviceDisconnected.firstWhere(
          (other) =>
              AlsaMidiDevice.hardwareId(other.cardId, other.deviceId) == id,
        );
        expect(device.connected, isTrue);
        device.disconnect();
        await disconnected;
        expect(device.connected, isFalse);
        break;
      }
    }
  });
}
```
