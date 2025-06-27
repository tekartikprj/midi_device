import 'dart:typed_data';

import 'package:flutter_midi_command/flutter_midi_command.dart' as fmc;
import 'package:tekartik_app_rx/helpers.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_common_utils/list_utils.dart';
import 'package:tekartik_midi_device/midi_device.dart';

/// Turn extra logs
var midiDeviceManagerFlutterCommandDebug = false;

void _log(Object message) {
  // ignore: avoid_print
  print(message);
}

/// Midi device manager for FLUTTERCOMMAND on Linux
MidiDeviceManager get midiDeviceManagerFlutterCommand =>
    _MidiDeviceManagerFlutterCommand();

class _MidiDeviceManagerFlutterCommand implements MidiDeviceManager {
  late final fmc.MidiCommand fmcMidiCommand = fmc.MidiCommand();
  final _connectedDevices = <String, _ConnectedMidiDeviceFlutterCommand>{};

  void addConnectedDevice(_ConnectedMidiDeviceFlutterCommand connectedDevice) {
    _connectedDevices[connectedDevice.id] = connectedDevice;
  }

  void removeConnectedDevice(
    _ConnectedMidiDeviceFlutterCommand connectedDevice,
  ) {
    _connectedDevices.remove(connectedDevice.id);
  }

  _ConnectedMidiDeviceFlutterCommand? connectedDeviceById(String deviceId) {
    return _connectedDevices[deviceId];
  }

  /// List of last known Midi devices.
  List<MidiDevice> _lastDevices = [];

  MidiDevice? _deviceById(String deviceId) {
    return _lastDevices.firstWhereOrNull((device) => device.id == deviceId);
  }

  @override
  Future<ConnectedMidiDevice> connectDevice(String deviceId) async {
    var connectedDevice = connectedDeviceById(deviceId);
    if (connectedDevice != null) {
      // Already connected
      return connectedDevice;
    }
    var device = _deviceById(deviceId);
    if (device == null) {
      await getDevices();
      device = _deviceById(deviceId);
    }
    if (device == null) {
      throw Exception('Device with id $deviceId not found');
    } else {
      var flutterCommandDevice = device.flutterCommandMidiDevice;
      if (!flutterCommandDevice.connected) {
        await fmcMidiCommand.connectToDevice(flutterCommandDevice);
        var connected = flutterCommandDevice.connected;
        if (midiDeviceManagerFlutterCommandDebug) {
          _log('FLUTTERCOMMAND device $deviceId connected: $connected');
        }
      }
      if (!flutterCommandDevice.connected) {
        throw Exception('Failed to connect to device with id $deviceId');
      }
      addConnectedDevice(_ConnectedMidiDeviceFlutterCommand(device._self));
      return _ConnectedMidiDeviceFlutterCommand(device._self);
    }
  }

  @override
  Future<List<MidiDevice>> getDevices() async {
    var flutterCommandDevices =
        (await fmcMidiCommand.devices) ?? <fmc.MidiDevice>[];
    if (midiDeviceManagerFlutterCommandDebug) {
      _log(
        'FLUTTERCOMMAND devices: ${flutterCommandDevices.map((d) => d.toDictionary)}',
      );
    }
    return _lastDevices = flutterCommandDevices
        .map(
          (flutterCommandDevice) =>
              _MidiDeviceFlutterCommand(this, flutterCommandDevice),
        )
        .toList();
  }
}

extension on MidiDevice {
  _MidiDeviceFlutterCommand get _self => this as _MidiDeviceFlutterCommand;

  fmc.MidiDevice get flutterCommandMidiDevice =>
      _self._flutterCommandMidiDevice;
}

class _MidiDeviceFlutterCommand implements MidiDevice {
  final _MidiDeviceManagerFlutterCommand _manager;
  final fmc.MidiDevice _flutterCommandMidiDevice;

  _MidiDeviceFlutterCommand(this._manager, this._flutterCommandMidiDevice);

  @override
  String get id => _flutterCommandMidiDevice.hwrId;

  @override
  int get inputPortCount => _flutterCommandMidiDevice.inputPorts.length;

  @override
  String get name => _flutterCommandMidiDevice.name;

  @override
  int get outputPortCount => _flutterCommandMidiDevice.outputPorts.length;

  @override
  Map<String, Object> toDebugMap() {
    return {
      'id': id,
      'name': name,
      'inputPortCount': inputPortCount,
      'outputPortCount': outputPortCount,
      if (midiDeviceManagerFlutterCommandDebug)
        'connected': _flutterCommandMidiDevice.connected,
    };
  }

  @override
  String toString() {
    return 'MidiDeviceFlutterCommand(${toDebugMap().toString()})';
  }
}

class _MidiMessageFlutterCommand implements MidiMessage {
  final _ConnectedMidiDeviceFlutterCommand _midiDevice;
  final fmc.MidiPacket _flutterCommandMidiMessage;

  _MidiMessageFlutterCommand(this._midiDevice, this._flutterCommandMidiMessage);

  @override
  int get timestamp => _flutterCommandMidiMessage.timestamp;

  @override
  Uint8List get data => _flutterCommandMidiMessage.data;

  @override
  ConnectedMidiDevice get device => _midiDevice;
}

class _ConnectedMidiDeviceFlutterCommand implements ConnectedMidiDevice {
  fmc.MidiCommand get fmcMidiCommand => _midiDevice._manager.fmcMidiCommand;
  final _MidiDeviceFlutterCommand _midiDevice;
  StreamSubscription? _deviceDisconnectedSubscription;

  _ConnectedMidiDeviceFlutterCommand(this._midiDevice) {
    /// Needed
    _deviceDisconnectedSubscription = fmcMidiCommand.onMidiSetupChanged?.listen(
      (_) async {
        var devices = await fmcMidiCommand.devices;
        if (devices != null) {
          for (var device in devices) {
            if (device.id == _midiDevice.id && device.connected) {
              /// Device is still connected
              return;
            }
          }
        }
        _disconnectedCompleter.safeComplete();
      },
    );

    /// Register this connected device with the manager
    onDisconnected.then((_) {
      // print('internal disconnect for device ${_midiDevice.id}');
      _disconnect();
    });
  }

  @override
  MidiDevice get device => _midiDevice;

  @override
  Future<void> disconnect() async {
    _disconnectedCompleter.safeComplete();
  }

  Future<void> _disconnect() async {
    _deviceDisconnectedSubscription?.cancel().unawait();
    _midiDevice._manager.removeConnectedDevice(this);
    _onMessageReceivedControllerOrNull?.close().unawait();
    fmcMidiCommand.disconnectDevice(_midiDevice.flutterCommandMidiDevice);
  }

  BroadcastStream<MidiMessage>? _onMessageReceivedControllerOrNull;
  late final _onMessageReceived = fmcMidiCommand.onMidiDataReceived!
      .where((packet) => packet.device.id == id)
      .map(
        (flutterCommandMidiMessage) =>
            _MidiMessageFlutterCommand(this, flutterCommandMidiMessage),
      )
      .toBroadcastStream();
  @override
  Stream<MidiMessage> get onMessageReceived =>
      (_onMessageReceivedControllerOrNull ??= _onMessageReceived);

  @override
  Future<void> sendData(Uint8List data) async {
    _midiDevice._manager.fmcMidiCommand.sendData(data, deviceId: id);
  }

  final _disconnectedCompleter = Completer<void>();

  @override
  Future<void> get onDisconnected => _disconnectedCompleter.future;

  Map<String, Object?> toDebugMap() {
    return {'id': id, 'name': name};
  }

  @override
  String toString() {
    return 'MidiDeviceFlutterCommand(${toDebugMap().toString()})';
  }
}

extension on fmc.MidiDevice {
  String get hwrId => id;
}
