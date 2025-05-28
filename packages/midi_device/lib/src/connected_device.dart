import 'dart:typed_data';

import 'package:tekartik_midi_device/midi_device.dart';

/// Represents a connected MIDI device that can send and receive MIDI messages.
abstract class ConnectedMidiDevice {
  /// Unique identifier for the connected MIDI device.
  MidiDevice get device;

  /// Closes the currently opened MIDI device.
  Future<void> disconnect();

  /// Sends a MIDI message to the currently opened device.
  Future<void> sendData(Uint8List data);

  /// Subscribes to MIDI messages from the currently opened device.
  Stream<MidiMessage> get onMessageReceived;

  /// Wait for disconnection.
  Future<void> get onDisconnected;
}

/// Helpers for [ConnectedMidiDevice].
extension ConnectedMidiDeviceExtension on ConnectedMidiDevice {
  /// Device name.
  String get name => device.name;

  /// Device ID.
  String get id => device.id;
}
