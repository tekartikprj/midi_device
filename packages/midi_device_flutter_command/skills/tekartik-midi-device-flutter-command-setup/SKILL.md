---
name: tekartik-midi-device-flutter-command-setup
description: >-
  Use when adding MIDI support to a Flutter app with
  tekartik_midi_device_flutter_command: midiDeviceManagerFlutterCommand (the
  flutter_midi_command backed MidiDeviceManager),
  midiDeviceManagerFlutterCommandDebug, the
  package:tekartik_midi_device_flutter_command/midi_device_flutter_command.dart
  import that re-exports MidiDevice/ConnectedMidiDevice/MidiMessage/
  MidiDeviceService, connectDevice/getDevices/sendData/onMessageReceived in
  widgets, and BLE MIDI scanning through the underlying MidiCommand.
---

# Flutter MIDI backend (tekartik_midi_device_flutter_command)

`tekartik_midi_device_flutter_command` implements the `tekartik_midi_device`
abstraction on top of the `flutter_midi_command` plugin, so a Flutter app gets
USB, virtual, network and BLE MIDI devices (Android, iOS, macOS, Linux,
Windows, web) behind the same portable `MidiDeviceManager` API.

## Guidelines

* Dependency (git only, not published on pub.dev):
  ```yaml
  dependencies:
    tekartik_midi_device_flutter_command:
      git:
        url: https://github.com/tekartikprj/midi_device
        path: packages/midi_device_flutter_command
  ```
  It brings `tekartik_midi_device` and `flutter_midi_command`; add
  `flutter_midi_command` explicitly only if you call it directly (BLE scan,
  virtual devices, network session).
* One import:
  `package:tekartik_midi_device_flutter_command/midi_device_flutter_command.dart`.
  It re-exports `package:tekartik_midi_device/midi_device.dart` (`MidiDevice`,
  `MidiDeviceManager`, `ConnectedMidiDevice`, `MidiMessage`,
  `MidiDeviceService`) and adds `midiDeviceManagerFlutterCommand` and
  `midiDeviceManagerFlutterCommandDebug`.
* `midiDeviceManagerFlutterCommand` is a getter that builds a **new** manager
  wrapper on every access (its connected-device cache is per instance, even
  though the underlying `MidiCommand` is a singleton). Read it once into a
  `final MidiDeviceManager` field/provider and reuse that instance for
  `getDevices()` and `connectDevice()`.
* Do the platform setup of `flutter_midi_command` in the app, not in shared
  code: Android bluetooth/location permissions, iOS/macOS bluetooth usage
  descriptions and background modes. Without them `getDevices()` simply returns
  the non BLE devices.
* `getDevices()` returns whatever the plugin currently knows; it never scans for
  BLE devices by itself. For BLE, call `MidiCommand().startBluetooth()` then
  `startScanningForBluetoothDevices()` from `package:flutter_midi_command`
  (import it with a prefix, it also declares a `MidiDevice` class), wait a few
  seconds, then call `getDevices()` again.
* `connectDevice(id)` throws a plain `Exception` when the id is unknown or when
  the plugin fails to connect; catch it and show a message. Keep the `id`
  (plugin device id), not the `MidiDevice` object, in your state.
* `onMessageReceived` is already filtered on the device and is a broadcast
  stream, so several widgets can listen. It dereferences the plugin's
  `onMidiDataReceived` stream: on a platform where the plugin provides none,
  the first listen throws; guard with a try/catch on unsupported targets.
* `sendData(Uint8List)` routes raw MIDI bytes to that device id
  (`[0x90, note, velocity]` note on, `[0x80, note, 0]` note off,
  `[0xb0, cc, value]` control change). It returns immediately, there is no
  delivery ack.
* `onDisconnected` completes when `disconnect()` is called or when the plugin's
  setup-changed event no longer lists the device as connected; use it to clear
  the UI state. Always `disconnect()` in `dispose()`.
* `MidiDeviceService(manager:, select:)` handles the usual app case (auto
  connect the first device whose name matches, reconnect after unplug):
  `start()` in `initState`, `stop()` in `dispose`, and build on
  `service.onDevice` / `service.onMessage`.
* `midiDeviceManagerFlutterCommandDebug = true` is the public log switch (the
  example app sets it in `main`); note it is currently a different variable
  from the internal one the implementation reads, so do not rely on the extra
  logs appearing.
* Testing: there is no fake backend here. Unit test against your own
  `MidiDeviceManager` fake from `tekartik_midi_device` and keep this package
  only in the composition root of the app.

## Examples

### Device list widget

```dart
import 'package:flutter/material.dart';
import 'package:tekartik_midi_device_flutter_command/midi_device_flutter_command.dart';

class MidiDeviceListScreen extends StatefulWidget {
  const MidiDeviceListScreen({super.key});

  @override
  State<MidiDeviceListScreen> createState() => _MidiDeviceListScreenState();
}

class _MidiDeviceListScreenState extends State<MidiDeviceListScreen> {
  final MidiDeviceManager manager = midiDeviceManagerFlutterCommand;
  late Future<List<MidiDevice>> _devicesFuture = manager.getDevices();
  ConnectedMidiDevice? _connected;

  @override
  void dispose() {
    _connected?.disconnect();
    super.dispose();
  }

  Future<void> _connect(MidiDevice device) async {
    try {
      var connected = await manager.connectDevice(device.id);
      connected.onMessageReceived.listen((message) {
        debugPrint('midi in ${message.data}');
      });
      connected.onDisconnected.then((_) {
        if (mounted) {
          setState(() => _connected = null);
        }
      });
      setState(() => _connected = connected);
    } catch (e) {
      debugPrint('connect failed $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_connected?.name ?? 'Midi devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                setState(() => _devicesFuture = manager.getDevices()),
          ),
        ],
      ),
      body: FutureBuilder<List<MidiDevice>>(
        future: _devicesFuture,
        builder: (context, snapshot) {
          var devices = snapshot.data ?? <MidiDevice>[];
          return ListView(
            children: [
              for (var device in devices)
                ListTile(
                  title: Text(device.name),
                  subtitle: Text(
                    '${device.id} in: ${device.inputPortCount} '
                    'out: ${device.outputPortCount}',
                  ),
                  selected: device.id == _connected?.id,
                  onTap: () => _connect(device),
                ),
            ],
          );
        },
      ),
    );
  }
}
```

### Send notes to the connected device

```dart
import 'dart:typed_data';

import 'package:tekartik_midi_device_flutter_command/midi_device_flutter_command.dart';

Future<void> playNote(
  ConnectedMidiDevice device,
  int note, {
  int channel = 0,
  int velocity = 127,
  Duration duration = const Duration(milliseconds: 300),
}) async {
  await device.sendData(Uint8List.fromList([0x90 | channel, note, velocity]));
  await Future<void>.delayed(duration);
  await device.sendData(Uint8List.fromList([0x80 | channel, note, 0]));
}
```

### Auto connect service in a stateful widget

```dart
import 'package:flutter/material.dart';
import 'package:tekartik_midi_device_flutter_command/midi_device_flutter_command.dart';

class MidiServiceScreen extends StatefulWidget {
  const MidiServiceScreen({super.key});

  @override
  State<MidiServiceScreen> createState() => _MidiServiceScreenState();
}

class _MidiServiceScreenState extends State<MidiServiceScreen> {
  late final MidiDeviceService service = MidiDeviceService(
    manager: midiDeviceManagerFlutterCommand,
    select: (device) => device.name.toLowerCase().contains('starlight'),
  );
  var _lastMessage = '';

  @override
  void initState() {
    super.initState();
    service.start();
    service.onMessage.listen((message) {
      if (mounted) {
        setState(() => _lastMessage = '${message.data}');
      }
    });
  }

  @override
  void dispose() {
    service.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConnectedMidiDevice?>(
      stream: service.onDevice,
      builder: (context, snapshot) {
        var device = snapshot.data;
        return Center(
          child: Text(
            device == null
                ? 'Waiting for device...'
                : '${device.name} ($_lastMessage)',
          ),
        );
      },
    );
  }
}
```

### Scan for BLE MIDI devices before listing

```dart
import 'package:flutter_midi_command/flutter_midi_command.dart' as fmc;
import 'package:tekartik_midi_device_flutter_command/midi_device_flutter_command.dart';

/// Starts a bluetooth scan, then lists what the manager sees.
Future<List<MidiDevice>> scanAndList(MidiDeviceManager manager) async {
  var midiCommand = fmc.MidiCommand();
  try {
    await midiCommand.startBluetooth();
    await midiCommand.startScanningForBluetoothDevices();
    await Future<void>.delayed(const Duration(seconds: 5));
  } catch (e) {
    // Missing permission or no bluetooth: keep the wired devices.
    print('bluetooth scan failed $e');
  } finally {
    midiCommand.stopScanningForBluetoothDevices();
  }
  return manager.getDevices();
}
```
