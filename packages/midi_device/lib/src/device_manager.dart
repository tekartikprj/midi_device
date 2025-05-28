import 'package:tekartik_midi_device/midi_device.dart';

/// Midi device manager interface.
abstract class MidiDeviceManager {
  /// Returns a list of all available MIDI devices.
  Future<List<MidiDevice>> getDevices();

  /// Opens a MIDI device by its ID.
  Future<ConnectedMidiDevice> connectDevice(String deviceId);
}
