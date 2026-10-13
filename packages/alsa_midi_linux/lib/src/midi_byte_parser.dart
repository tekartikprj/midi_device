import 'dart:typed_data';

/// Length of the message started by a status byte: 1 to 3, -1 for a sysex
/// (ends with 0xF7), 0 for a data byte or an undefined/ignored status
/// (0xF4, 0xF5, a lone 0xF7).
int midiStatusLength(int status) {
  if (status >= 0xF8) {
    // Real-time
    return 1;
  }
  switch (status & 0xF0) {
    case 0x80:
    case 0x90:
    case 0xA0:
    case 0xB0:
    case 0xE0:
      return 3;
    case 0xC0:
    case 0xD0:
      return 2;
    default:
      break;
  }
  switch (status) {
    case 0xF0:
      return -1;
    case 0xF1:
    case 0xF3:
      return 2;
    case 0xF2:
      return 3;
    case 0xF6:
      return 1;
    default:
      return 0;
  }
}

/// Splits a raw MIDI byte stream into complete messages.
///
/// Handles running status (data bytes reusing the last channel status byte),
/// real-time bytes (0xF8-0xFF) interleaved anywhere, including inside another
/// message or a sysex, and sysex messages (0xF0 ... 0xF7).
class MidiByteParser {
  final _buffer = <int>[];

  /// Last channel status byte, null after a system common message.
  int? _runningStatus;

  /// Expected length of the message in progress, -1 for a sysex, 0 if none.
  var _expectedLength = 0;

  /// Add a received byte, returns the messages completed by this byte
  /// (none or one).
  List<Uint8List> add(int byte) {
    byte &= 0xFF;
    if (byte >= 0xF8) {
      // Real-time: a single byte message that does not change the message in
      // progress nor the running status.
      return [
        Uint8List.fromList([byte]),
      ];
    }
    if (byte >= 0x80) {
      if (byte == 0xF7 && _expectedLength == -1) {
        _buffer.add(byte);
        return _flush();
      }
      // Any other status byte drops an incomplete message or sysex.
      _buffer.clear();
      // A channel status sets the running status, a system common clears it.
      _runningStatus = byte < 0xF0 ? byte : null;
      var length = midiStatusLength(byte);
      _expectedLength = length;
      if (length == 0) {
        // Undefined or a lone end of sysex: ignored.
        return const [];
      }
      _buffer.add(byte);
      if (length == 1) {
        return _flush();
      }
      return const [];
    }
    // Data byte
    if (_expectedLength == -1) {
      _buffer.add(byte);
      return const [];
    }
    if (_buffer.isEmpty) {
      var status = _runningStatus;
      if (status == null) {
        // Data byte without a status: ignored.
        return const [];
      }
      // Running status
      _buffer.add(status);
      _expectedLength = midiStatusLength(status);
    }
    _buffer.add(byte);
    if (_buffer.length == _expectedLength) {
      return _flush();
    }
    return const [];
  }

  List<Uint8List> _flush() {
    var message = Uint8List.fromList(_buffer);
    _buffer.clear();
    _expectedLength = 0;
    return [message];
  }
}
