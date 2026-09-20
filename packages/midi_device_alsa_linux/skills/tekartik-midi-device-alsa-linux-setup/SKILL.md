---
name: tekartik-midi-device-alsa-linux-setup
description: >-
  Use when wiring the ALSA Linux MIDI backend into tekartik_midi_device code:
  midiDeviceManagerAlsaLinux (the MidiDeviceManager implementation),
  midiDeviceManagerAlsaLinuxDebug, the
  package:tekartik_midi_device_alsa_linux/midi_device_alsa_linux.dart import
  that re-exports MidiDevice/ConnectedMidiDevice/MidiMessage/MidiDeviceService,
  the hw:card,device ids, and guarding against the UnsupportedError thrown off
  Linux/on the web.
---

# ALSA Linux MIDI device manager (tekartik_midi_device_alsa_linux)

`tekartik_midi_device_alsa_linux` implements the `tekartik_midi_device`
abstraction on top of `tekartik_alsa_midi_linux` (ALSA raw MIDI over FFI). It
is the Linux desktop backend: plug it in, then write everything else against
the portable `MidiDeviceManager` API.

## Guidelines

* Dependency (git only, not published on pub.dev):
  ```yaml
  dependencies:
    tekartik_midi_device_alsa_linux:
      git:
        url: https://github.com/tekartikprj/midi_device
        path: packages/midi_device_alsa_linux
  ```
  It pulls `tekartik_midi_device` and `tekartik_alsa_midi_linux` from the same
  repo; depend on `tekartik_midi_device` explicitly for shared code.
* One import: `package:tekartik_midi_device_alsa_linux/midi_device_alsa_linux.dart`.
  It re-exports the whole `package:tekartik_midi_device/midi_device.dart` API
  (`MidiDevice`, `MidiDeviceManager`, `ConnectedMidiDevice`, `MidiMessage`,
  `MidiDeviceService`) and adds `midiDeviceManagerAlsaLinux` and
  `midiDeviceManagerAlsaLinuxDebug`. Nothing else is public.
* `midiDeviceManagerAlsaLinux` is a getter that builds a **new** manager on
  every access, each with its own connected device cache. Read it once into a
  `final MidiDeviceManager` variable (or pass it to a `MidiDeviceService`) and
  reuse that instance; never call `midiDeviceManagerAlsaLinux.connectDevice()`
  and then `midiDeviceManagerAlsaLinux.getDevices()` as two separate accesses.
* Platform: Linux VM / Flutter desktop only, with `libasound.so.2` installed.
  On the web the getter throws `UnsupportedError('Only on linux')` (the
  conditional import makes it safe to import in web code as long as you do not
  touch it). On macOS/Windows nothing guards you: check `Platform.isLinux`
  before using it, exactly like the example app does.
* Device `id` is the ALSA hardware id, `'hw:<card>,<device>'`, and `name` is the
  sound card short name (the same name can appear several times, ids differ).
  `inputPortCount`/`outputPortCount` are the ALSA subdevice counts. Persist the
  `id`, not the `MidiDevice` instance.
* `connectDevice(id)` throws a plain `Exception` when the id is unknown (after
  a rescan) or when ALSA refuses to open the device (usually another process
  holds it). Wrap it in a try/catch; a failed connect is a normal situation.
* The returned `ConnectedMidiDevice` sends with `sendData(Uint8List)` (raw
  bytes, status first), receives on `onMessageReceived` and completes
  `onDisconnected` both when you call `disconnect()` and when ALSA reports the
  device gone. Always `disconnect()`: it closes the ALSA ports and kills the
  receive isolate.
* `onMessageReceived` is a broadcast stream, but it delivers every message of
  the underlying ALSA scan, clock (`0xf8`) and active sensing (`0xfe`)
  included; filter in your handler.
* `MidiDeviceService(manager: midiDeviceManagerAlsaLinux, select: ...)` is the
  usual desktop setup: it polls, auto connects the matching device and
  reconnects after unplug.
* `midiDeviceManagerAlsaLinuxDebug = true` is the public log switch (the
  example app sets it at startup); note it is currently a different variable
  from the internal one the implementation reads, so do not rely on the extra
  logs appearing.
* Tests: `dart test` with `@TestOn('vm')` plus a `Platform.isLinux` skip, and
  expect zero devices on a CI machine. A non-VM test can only assert that
  touching the getter throws `UnsupportedError` on the web.

## Examples

### List, connect, send and receive from a CLI

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:tekartik_midi_device_alsa_linux/midi_device_alsa_linux.dart';

Future<void> main() async {
  if (!Platform.isLinux) {
    stderr.writeln('alsa midi is linux only');
    return;
  }
  final MidiDeviceManager manager = midiDeviceManagerAlsaLinux;
  var devices = await manager.getDevices();
  for (var device in devices) {
    print(device.toDebugMap());
  }
  if (devices.isEmpty) {
    return;
  }
  ConnectedMidiDevice connected;
  try {
    connected = await manager.connectDevice(devices.first.id);
  } catch (e) {
    print('connect failed: $e');
    return;
  }
  var subscription = connected.onMessageReceived.listen((message) {
    if (message.data.first != 0xf8) {
      print('${message.timestamp} ${message.data}');
    }
  });
  await connected.sendData(Uint8List.fromList([0x90, 60, 127]));
  await Future<void>.delayed(const Duration(seconds: 5));
  await subscription.cancel();
  await connected.disconnect();
}
```

### Auto connect a named device with MidiDeviceService

```dart
import 'dart:io';

import 'package:tekartik_midi_device_alsa_linux/midi_device_alsa_linux.dart';

MidiDeviceService? newAlsaService(String nameMatch) {
  if (!Platform.isLinux) {
    return null;
  }
  var service = MidiDeviceService(
    manager: midiDeviceManagerAlsaLinux,
    select: (device) =>
        device.name.toLowerCase().contains(nameMatch.toLowerCase()),
  );
  service.onDevice.listen((device) {
    print(device == null ? 'no device' : 'connected ${device.name} ${device.id}');
  });
  service.onMessage.listen((message) => print('in ${message.data}'));
  service.start();
  return service;
}
```

### Pick the backend once, keep the rest portable

```dart
import 'package:tekartik_midi_device/midi_device.dart';
import 'package:tekartik_midi_device_alsa_linux/midi_device_alsa_linux.dart'
    show midiDeviceManagerAlsaLinux;

/// Null when the current platform has no ALSA backend (web, macOS, Windows).
MidiDeviceManager? get midiDeviceManagerOrNull {
  try {
    return midiDeviceManagerAlsaLinux;
  } on UnsupportedError catch (_) {
    return null;
  }
}

Future<void> dumpDevices(MidiDeviceManager manager) async {
  for (var device in await manager.getDevices()) {
    print('${device.id} ${device.name} '
        '${device.inputPortCount}/${device.outputPortCount}');
  }
}
```

### Linux only test

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:tekartik_midi_device_alsa_linux/midi_device_alsa_linux.dart';
import 'package:test/test.dart';

void main() {
  group('alsa linux', () {
    test('getDevices', () async {
      var manager = midiDeviceManagerAlsaLinux;
      var devices = await manager.getDevices();
      for (var device in devices) {
        expect(device.id, startsWith('hw:'));
      }
    });
  }, skip: !Platform.isLinux);
}
```
