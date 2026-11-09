import 'dart:typed_data';

import 'alsa_midi_device.dart';

/// A complete MIDI message received from [device].
class MidiMessage {
  /// When it arrived, in milliseconds since epoch (local clock, not ALSA's).
  int timestamp;

  /// The bytes, status byte first (a sysex from 0xF0 to 0xF7).
  Uint8List data;

  /// The device it comes from.
  AlsaMidiDevice device;

  /// A message.
  MidiMessage(this.data, this.timestamp, this.device);

  Map<String, Object> get toDictionary {
    return {
      'data': data,
      'timestamp': timestamp,
      'sender': device.toDictionary,
    };
  }

  @override
  String toString() {
    return toDictionary.toString();
  }
}
