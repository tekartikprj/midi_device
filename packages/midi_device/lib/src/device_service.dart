import 'package:tekartik_app_rx/helpers.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_common_utils/env_utils.dart';
import 'package:tekartik_midi_device/midi_device.dart';

/// Device selection funnction
typedef MidiDeviceSelectFunction = bool Function(MidiDevice);

/// Midi device service
class MidiDeviceService {
  var _started = false;

  /// Device manager
  final MidiDeviceManager manager;

  final _subject = BehaviorSubject<ConnectedMidiDevice?>();

  /// Stream of connected device matching the select function (one only)
  ValueStream<ConnectedMidiDevice?> get onDevice => _subject.stream;

  /// Incoming stream of message
  Stream<MidiMessage> get onMessage async* {
    await for (var device in onDevice) {
      if (device != null) {
        yield* device.onMessageReceived;
      }
    }
  }

  /// Select function to select a device
  final MidiDeviceSelectFunction select;

  /// Device service constructor
  MidiDeviceService({required this.manager, required this.select});

  final _lock = Lock();
  final _loopLock = Lock();

  /// start the device service
  void start() {
    if (_started) {
      return;
    }
    _started = true;
    if (_loopLock.locked) {
      // If the loop is already running, do not start it again
      return;
    }
    _loopLock.synchronized(() async {
      while (_started) {
        try {
          // Get the list of devices
          var devices = await manager.getDevices();
          if (devices.isNotEmpty) {
            // If a select function is provided, filter the devices

            devices = devices.where(select).toList();

            // If there are selected devices, connect to the first one
            if (devices.isNotEmpty) {
              for (var device in devices) {
                late ConnectedMidiDevice connectedDevice;
                await _lock.synchronized(() async {
                  connectedDevice = await manager.connectDevice(device.id);
                  _subject.add(connectedDevice);
                });
                // Check if the device is already connected
                await connectedDevice.onDisconnected;
              }
            }
          }
        } catch (e) {
          // Handle any errors that occur during device retrieval or connection
          if (isDebug) {
            // ignore: avoid_print
            print('Error in MidiDeviceService: $e');
          }
        }
        _subject.add(null); // Emit null to indicate no device is connected
        if (!_started) {
          return; // Exit if the service has been stopped
        }
        await sleep(5000); // Wait before retrying
      }
    });
  }

  /// Stop the device service
  void stop() {
    if (!_started) {
      return;
    }
    _started = false;

    _lock.synchronized(() async {
      var connectedDevice = _subject.value;
      await connectedDevice?.disconnect();
    });
  }
}
