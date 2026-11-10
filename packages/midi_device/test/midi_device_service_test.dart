import 'dart:async';
import 'dart:typed_data';

import 'package:tekartik_midi_device/midi_device.dart';
import 'package:test/test.dart';

class _FakeDevice implements MidiDevice {
  @override
  final String id;

  _FakeDevice(this.id);

  @override
  String get name => 'fake $id';

  @override
  int get inputPortCount => 1;

  @override
  int get outputPortCount => 1;

  @override
  Map<String, Object> toDebugMap() => {'id': id};
}

class _FakeConnected implements ConnectedMidiDevice {
  @override
  final MidiDevice device;
  final _disconnected = Completer<void>();
  final _messages = StreamController<MidiMessage>.broadcast();

  _FakeConnected(this.device);

  bool get connected => !_disconnected.isCompleted;

  @override
  Future<void> disconnect() async {
    if (!_disconnected.isCompleted) {
      _disconnected.complete();
    }
    await _messages.close();
  }

  @override
  Stream<MidiMessage> get onMessageReceived => _messages.stream;

  @override
  Future<void> get onDisconnected => _disconnected.future;

  @override
  Future<void> sendData(Uint8List data) async {}
}

class _FakeManager implements MidiDeviceManager {
  final List<MidiDevice> devices;
  final _listing = <Completer<void>>[];
  final connected = <_FakeConnected>[];

  /// When true, [getDevices] waits for [list].
  final bool manual;

  _FakeManager(this.devices, {this.manual = false});

  /// Ends the pending [getDevices] calls.
  void list() {
    for (var completer in _listing) {
      completer.complete();
    }
    _listing.clear();
  }

  @override
  Future<List<MidiDevice>> getDevices() async {
    if (manual) {
      var completer = Completer<void>();
      _listing.add(completer);
      await completer.future;
    }
    return devices;
  }

  @override
  Future<ConnectedMidiDevice> connectDevice(String deviceId) async {
    var device = _FakeConnected(devices.firstWhere((d) => d.id == deviceId));
    connected.add(device);
    return device;
  }

  List<String> get connectedIds => [
    for (var device in connected)
      if (device.connected) device.device.id,
  ];

  Future<void> disconnectAll() async {
    for (var device in connected) {
      await device.disconnect();
    }
  }
}

/// Lets the service loop run (no timer of the 5 s wait fires).
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('MidiDeviceService', () {
    test('connects the first matching device, stop disconnects it', () async {
      var manager = _FakeManager([_FakeDevice('1'), _FakeDevice('2')]);
      var service = MidiDeviceService(
        manager: manager,
        select: (device) => device.id == '2',
      );
      service.start();
      await _settle();
      expect(service.onDevice.valueOrNull?.id, '2');
      expect(manager.connectedIds, ['2']);
      service.stop();
      await _settle();
      expect(manager.connectedIds, isEmpty);
      expect(service.onDevice.valueOrNull, isNull);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('stop before any device was listed', () async {
      var manager = _FakeManager([_FakeDevice('1')], manual: true);
      var service = MidiDeviceService(manager: manager, select: (_) => true);
      var errors = <Object>[];
      await runZonedGuarded(() async {
        service.start();
        await _settle();
        // getDevices() pending: nothing emitted yet.
        service.stop();
        await _settle();
        manager.list();
        await _settle();
      }, (error, _) => errors.add(error));
      expect(errors, isEmpty);
      // Not connected after the stop.
      expect(manager.connectedIds, isEmpty);
      expect(service.onDevice.valueOrNull, isNull);
      await manager.disconnectAll();
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('stop with two matching devices connects none', () async {
      var manager = _FakeManager([_FakeDevice('1'), _FakeDevice('2')]);
      var service = MidiDeviceService(manager: manager, select: (_) => true);
      service.start();
      await _settle();
      expect(manager.connectedIds, ['1']);
      service.stop();
      await _settle();
      expect(manager.connectedIds, isEmpty);
      expect(service.onDevice.valueOrNull, isNull);
      await manager.disconnectAll();
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}
