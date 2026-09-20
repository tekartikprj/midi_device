---
name: tekartik-midi-device-setup
description: >-
  Use when listing, connecting to or streaming from MIDI devices through the
  tekartik_midi_device abstraction, or when implementing a new backend for it:
  MidiDeviceManager (getDevices, connectDevice), MidiDevice (id, name,
  inputPortCount, outputPortCount, toDebugMap), ConnectedMidiDevice (sendData,
  onMessageReceived, onDisconnected, disconnect), MidiMessage (timestamp, data,
  device), MidiDeviceService with its select/MidiDeviceSelectFunction auto
  connect loop, and the package:tekartik_midi_device/midi_device.dart import.
---

# MIDI device abstraction (tekartik_midi_device)

`tekartik_midi_device` only defines the platform independent MIDI device
interfaces plus a small auto connect service. It contains no platform code: a
concrete `MidiDeviceManager` comes from an implementation package
(`tekartik_midi_device_alsa_linux` on Linux, `tekartik_midi_device_flutter_command`
on Flutter).

## Guidelines

* Dependency (git only, not published on pub.dev):
  ```yaml
  dependencies:
    tekartik_midi_device:
      git:
        url: https://github.com/tekartikprj/midi_device
        path: packages/midi_device
  ```
  Add an implementation package too; write shared code against this one.
* Single import: `package:tekartik_midi_device/midi_device.dart`. It exports
  `MidiDevice`, `MidiDeviceManager`, `ConnectedMidiDevice`,
  `ConnectedMidiDeviceExtension`, `MidiMessage`, `MidiDeviceService` and
  `MidiDeviceSelectFunction`. There is nothing else to import; `lib/src` is
  private.
* `MidiDeviceManager` has exactly two members: `getDevices()` returning
  `Future<List<MidiDevice>>` and `connectDevice(String deviceId)` returning
  `Future<ConnectedMidiDevice>`. Implementation packages expose a ready made
  top level manager instance, never a constructor you call from shared code.
* `MidiDevice` is a description only (`id`, `name`, `inputPortCount`,
  `outputPortCount`, `toDebugMap()`); it carries no connection. Always keep the
  `id` and reconnect with it, the `MidiDevice` objects are recreated on each
  `getDevices()` call and must not be compared by identity.
* `ConnectedMidiDevice` is the live connection: `sendData(Uint8List)`,
  `onMessageReceived` (a `Stream<MidiMessage>`), `onDisconnected` (a `Future`
  that completes when the device goes away) and `disconnect()`. The
  `ConnectedMidiDeviceExtension` adds the `name` and `id` shortcuts of the
  underlying `device`.
* Always `await disconnect()` when leaving a screen or a command, and use
  `onDisconnected` (not an error on the message stream) to detect unplugging.
* `sendData` takes raw MIDI bytes as a `Uint8List`, status byte first, e.g.
  `Uint8List.fromList([0x90, 60, 127])` for a note on. This package does not
  parse or build messages; incoming bytes arrive as `MidiMessage.data` with a
  backend specific `timestamp` and the originating `device`.
* `MidiDeviceService(manager:, select:)` is the auto connect loop: call
  `start()` once, it polls `getDevices()`, keeps the first device matching
  `select` connected, re-scans every 5 seconds and after each disconnection,
  and `stop()` disconnects. `select` is a `MidiDeviceSelectFunction`
  (`bool Function(MidiDevice)`), typically a name match.
* `service.onDevice` is a `ValueStream<ConnectedMidiDevice?>` (rxdart, through
  `tekartik_app_rx`): `null` means currently not connected. Read the current
  value with `valueOrNull` (`value` throws before the first event) and listen
  for changes. `service.onMessage` flattens the messages of whichever device is
  connected, so UI code never has to re-subscribe.
* One `MidiDeviceService` per selection: it holds a single connection, not a
  list. To drive several devices at once, use `manager.connectDevice()`
  directly per device.
* Anti-patterns: calling `getDevices()` in a tight loop (the service already
  polls), keeping a `ConnectedMidiDevice` after `onDisconnected` completed,
  assuming `getDevices()` is cheap or synchronous, or importing the
  implementation package from shared code instead of taking a
  `MidiDeviceManager` parameter.
* Tests: implement the four interfaces in memory (see the last example) and
  inject that manager; no platform MIDI backend is needed.

## Examples

### List devices, connect, receive and send

```dart
import 'dart:typed_data';

import 'package:tekartik_midi_device/midi_device.dart';

Future<void> playNote(MidiDeviceManager manager) async {
  var devices = await manager.getDevices();
  for (var device in devices) {
    print('${device.name} (${device.id}) ${device.toDebugMap()}');
  }
  var found = devices.firstWhere((device) => device.outputPortCount > 0);

  var connected = await manager.connectDevice(found.id);
  var subscription = connected.onMessageReceived.listen((message) {
    print('${message.timestamp} from ${message.device.name}: ${message.data}');
  });
  try {
    await connected.sendData(Uint8List.fromList([0x90, 60, 127])); // note on
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await connected.sendData(Uint8List.fromList([0x80, 60, 0])); // note off
  } finally {
    await subscription.cancel();
    await connected.disconnect();
  }
}
```

### Auto connect service on a device name

```dart
import 'dart:typed_data';

import 'package:tekartik_midi_device/midi_device.dart';

Future<void> autoConnect(MidiDeviceManager manager) async {
  var service = MidiDeviceService(
    manager: manager,
    select: (device) => device.name.toLowerCase().contains('starlight'),
  );
  service.onDevice.listen((device) {
    print(device == null ? 'disconnected' : 'connected ${device.name}');
  });
  service.onMessage.listen((message) {
    print('in: ${message.data}');
  });
  service.start();

  await Future<void>.delayed(const Duration(seconds: 10));
  await service.onDevice.valueOrNull?.sendData(Uint8List.fromList([0xb0, 7, 100]));
  service.stop();
}
```

### An in memory manager for tests

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:tekartik_midi_device/midi_device.dart';

class FakeMidiDevice implements MidiDevice {
  @override
  final String id;
  @override
  final String name;
  FakeMidiDevice({required this.id, required this.name});
  @override
  int get inputPortCount => 1;
  @override
  int get outputPortCount => 1;
  @override
  Map<String, Object> toDebugMap() => {'id': id, 'name': name};
}

class FakeConnectedMidiDevice implements ConnectedMidiDevice {
  @override
  final MidiDevice device;
  final sentData = <Uint8List>[];
  final _messageController = StreamController<MidiMessage>.broadcast();
  final _disconnected = Completer<void>();
  FakeConnectedMidiDevice(this.device);

  /// Simulate an incoming message.
  void receive(Uint8List data) => _messageController.add(
    FakeMidiMessage(device: this, data: data, timestamp: 0),
  );

  @override
  Stream<MidiMessage> get onMessageReceived => _messageController.stream;
  @override
  Future<void> get onDisconnected => _disconnected.future;
  @override
  Future<void> sendData(Uint8List data) async => sentData.add(data);
  @override
  Future<void> disconnect() async {
    if (!_disconnected.isCompleted) {
      _disconnected.complete();
    }
    await _messageController.close();
  }
}

class FakeMidiMessage implements MidiMessage {
  @override
  final ConnectedMidiDevice device;
  @override
  final Uint8List data;
  @override
  final int timestamp;
  FakeMidiMessage({
    required this.device,
    required this.data,
    required this.timestamp,
  });
}

class FakeMidiDeviceManager implements MidiDeviceManager {
  final devices = <MidiDevice>[FakeMidiDevice(id: '1', name: 'Fake device')];
  @override
  Future<List<MidiDevice>> getDevices() async => devices;
  @override
  Future<ConnectedMidiDevice> connectDevice(String deviceId) async =>
      FakeConnectedMidiDevice(devices.firstWhere((d) => d.id == deviceId));
}
```
