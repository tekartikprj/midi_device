import 'dart:typed_data';

import '../midi_device.dart';

/// Represents a received MIDI message with its associated data, timestamp, and device.
abstract class MidiMessage {
  /// The timestamp of the MIDI message, typically in milliseconds.
  int get timestamp;

  /// The data of the MIDI message, represented as a list of bytes.
  Uint8List get data;

  /// The device that sent the MIDI message.
  ConnectedMidiDevice get device;
}
