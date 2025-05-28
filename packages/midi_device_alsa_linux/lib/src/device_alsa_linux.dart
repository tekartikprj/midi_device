import 'dart:typed_data';

import 'package:tekartik_alsa_midi_linux/midi.dart' as alsa;
import 'package:tekartik_app_rx/helpers.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_common_utils/list_utils.dart';
import 'package:tekartik_midi_device/midi_device.dart';

/// Turn extra logs
var midiDeviceManagerAlsaLinuxDebug = false;

void _log(Object message) {
  // ignore: avoid_print
  print(message);
}

/// Midi device manager for ALSA on Linux
MidiDeviceManager get midiDeviceManagerAlsaLinux =>
    _MidiDeviceManagerAlsaLinux();

class _MidiDeviceManagerAlsaLinux implements MidiDeviceManager {
  final _connectedDevices = <String, _ConnectedMidiDeviceAlsaLinux>{};

  void addConnectedDevice(_ConnectedMidiDeviceAlsaLinux connectedDevice) {
    _connectedDevices[connectedDevice.id] = connectedDevice;
  }

  void removeConnectedDevice(_ConnectedMidiDeviceAlsaLinux connectedDevice) {
    _connectedDevices.remove(connectedDevice.id);
  }

  _ConnectedMidiDeviceAlsaLinux? connectedDeviceById(String deviceId) {
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
      var alsaDevice = device.alsaMidiDevice;
      if (!alsaDevice.connected) {
        var connected = await alsaDevice.connect();
        if (midiDeviceManagerAlsaLinuxDebug) {
          _log('ALSA device $deviceId connected: $connected');
        }
      }
      if (!alsaDevice.connected) {
        throw Exception('Failed to connect to device with id $deviceId');
      }
      addConnectedDevice(_ConnectedMidiDeviceAlsaLinux(device._self));
      return _ConnectedMidiDeviceAlsaLinux(device._self);
    }
  }

  @override
  Future<List<MidiDevice>> getDevices() async {
    var alsaDevices = alsa.AlsaMidiDevice.getDevices();
    if (midiDeviceManagerAlsaLinuxDebug) {
      _log('ALSA devices: ${alsaDevices.map((d) => d.toDictionary)}');
    }
    return _lastDevices =
        alsaDevices
            .map((alsaDevice) => _MidiDeviceAlsaLinux(this, alsaDevice))
            .toList();
  }
}

extension on MidiDevice {
  _MidiDeviceAlsaLinux get _self => this as _MidiDeviceAlsaLinux;

  alsa.AlsaMidiDevice get alsaMidiDevice => _self._alsaMidiDevice;
}

class _MidiDeviceAlsaLinux implements MidiDevice {
  final _MidiDeviceManagerAlsaLinux _manager;
  final alsa.AlsaMidiDevice _alsaMidiDevice;

  _MidiDeviceAlsaLinux(this._manager, this._alsaMidiDevice);

  @override
  String get id => _alsaMidiDevice.hwrId;

  @override
  int get inputPortCount => _alsaMidiDevice.inputPorts.length;

  @override
  String get name => _alsaMidiDevice.name;

  @override
  int get outputPortCount => _alsaMidiDevice.outputPorts.length;

  @override
  Map<String, Object> toDebugMap() {
    return {
      'id': id,
      'name': name,
      'inputPortCount': inputPortCount,
      'outputPortCount': outputPortCount,
      if (midiDeviceManagerAlsaLinuxDebug)
        'connected': _alsaMidiDevice.connected,
    };
  }

  @override
  String toString() {
    return 'MidiDeviceAlsaLinux(${toDebugMap().toString()})';
  }
}

class _MidiMessageAlsaLinux implements MidiMessage {
  final _ConnectedMidiDeviceAlsaLinux _midiDevice;
  final alsa.MidiMessage _alsaMidiMessage;

  _MidiMessageAlsaLinux(this._midiDevice, this._alsaMidiMessage);

  @override
  int get timestamp => _alsaMidiMessage.timestamp;

  @override
  Uint8List get data => _alsaMidiMessage.data;

  @override
  ConnectedMidiDevice get device => _midiDevice;
}

class _ConnectedMidiDeviceAlsaLinux implements ConnectedMidiDevice {
  final _MidiDeviceAlsaLinux _midiDevice;
  late StreamSubscription _deviceDisconnectedSubscription;

  _ConnectedMidiDeviceAlsaLinux(this._midiDevice) {
    /// Needed
    _deviceDisconnectedSubscription = alsa.AlsaMidiDevice.onDeviceDisconnected
        .where((device) => device.hwrId == _midiDevice.id)
        .listen((_) {
          _disconnectedCompleter.safeComplete();
        });

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
    _deviceDisconnectedSubscription.cancel().unawait();
    _midiDevice._manager.removeConnectedDevice(this);
    _onMessageReceivedControllerOrNull?.close().unawait();
    _midiDevice._alsaMidiDevice.disconnect();
  }

  BroadcastStream<MidiMessage>? _onMessageReceivedControllerOrNull;
  late final _onMessageReceived =
      _midiDevice._alsaMidiDevice.receivedMessages
          .map(
            (alsaMidiMessage) => _MidiMessageAlsaLinux(this, alsaMidiMessage),
          )
          .toBroadcastStream();
  @override
  Stream<MidiMessage> get onMessageReceived =>
      (_onMessageReceivedControllerOrNull ??= _onMessageReceived);

  @override
  Future<void> sendData(Uint8List data) async {
    _midiDevice._alsaMidiDevice.send(data);
  }

  final _disconnectedCompleter = Completer<void>();

  @override
  Future<void> get onDisconnected => _disconnectedCompleter.future;

  Map<String, Object?> toDebugMap() {
    return {'id': id, 'name': name};
  }

  @override
  String toString() {
    return 'MidiDeviceAlsaLinux(${toDebugMap().toString()})';
  }
}

extension on alsa.AlsaMidiDevice {
  String get hwrId => alsa.AlsaMidiDevice.hardwareId(cardId, deviceId);
}
