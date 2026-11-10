// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:typed_data';

import 'package:tekartik_midi_device/midi_device.dart';

/// A device in memory: it echoes what it is sent.
class EchoMidiDevice implements MidiDevice {
  @override
  final String id;

  @override
  final String name;

  /// A device [id] named [name].
  EchoMidiDevice(this.id, this.name);

  @override
  int get inputPortCount => 1;

  @override
  int get outputPortCount => 1;

  @override
  Map<String, Object> toDebugMap() => {'id': id, 'name': name};
}

class _EchoMessage implements MidiMessage {
  @override
  final ConnectedMidiDevice device;

  @override
  final Uint8List data;

  @override
  final int timestamp;

  _EchoMessage(this.device, this.data, this.timestamp);
}

class _EchoConnected implements ConnectedMidiDevice {
  @override
  final MidiDevice device;
  final _messages = StreamController<MidiMessage>.broadcast();
  final _disconnected = Completer<void>();
  final _clock = Stopwatch()..start();

  _EchoConnected(this.device);

  @override
  Future<void> sendData(Uint8List data) async {
    _messages.add(_EchoMessage(this, data, _clock.elapsedMilliseconds));
  }

  @override
  Stream<MidiMessage> get onMessageReceived => _messages.stream;

  @override
  Future<void> get onDisconnected => _disconnected.future;

  @override
  Future<void> disconnect() async {
    if (!_disconnected.isCompleted) {
      _disconnected.complete();
    }
    await _messages.close();
  }
}

/// A manager of echo devices: what a test, or a demo, uses instead of a
/// platform one (`midiDeviceManagerAlsaLinux`...).
class EchoMidiDeviceManager implements MidiDeviceManager {
  /// The devices.
  final devices = <MidiDevice>[EchoMidiDevice('1', 'Echo keyboard')];

  @override
  Future<List<MidiDevice>> getDevices() async => devices;

  @override
  Future<ConnectedMidiDevice> connectDevice(String deviceId) async =>
      _EchoConnected(devices.firstWhere((device) => device.id == deviceId));
}

/// Plays a note on the first device with an output, prints what it sends.
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
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await connected.sendData(Uint8List.fromList([0x80, 60, 0]));
  } finally {
    await subscription.cancel();
    await connected.disconnect();
  }
}

Future<void> main() async {
  var manager = EchoMidiDeviceManager();
  await playNote(manager);

  // The service keeps the selected device connected.
  var service = MidiDeviceService(
    manager: manager,
    select: (device) => device.name.toLowerCase().contains('keyboard'),
  );
  var subscription = service.onMessage.listen((message) {
    print('service: ${message.data}');
  });
  service.start();
  var device = await service.onDevice.firstWhere((device) => device != null);
  print('connected ${device!.name}');
  // onMessage follows the new device from the next event loop turn.
  await Future<void>.delayed(Duration.zero);
  await device.sendData(Uint8List.fromList([0xb0, 7, 100])); // volume
  await Future<void>.delayed(const Duration(milliseconds: 100));
  service.stop();
  await service.onDevice.firstWhere((device) => device == null);
  print('stopped');
  await subscription.cancel();
}
