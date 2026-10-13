import 'package:tekartik_alsa_midi_linux/alsa_midi_device.dart';
import 'package:tekartik_alsa_midi_linux/src/midi_byte_parser.dart';
import 'package:test/test.dart';

/// Parse all the bytes, returns the messages.
List<List<int>> parse(List<int> bytes) {
  var parser = MidiByteParser();
  return [
    for (var byte in bytes)
      ...parser.add(byte).map((message) => message.toList()),
  ];
}

void main() {
  group('midi_byte_parser', () {
    test('channel messages', () {
      expect(parse([0x90, 60, 100, 0xC0, 5, 0x80, 60, 0]), [
        [0x90, 60, 100],
        [0xC0, 5],
        [0x80, 60, 0],
      ]);
    });
    test('running status', () {
      // Note on, then 2 more notes without the status byte.
      expect(parse([0x90, 60, 100, 62, 100, 64, 0]), [
        [0x90, 60, 100],
        [0x90, 62, 100],
        [0x90, 64, 0],
      ]);
      // Program change running status (2 bytes)
      expect(parse([0xC0, 1, 2]), [
        [0xC0, 1],
        [0xC0, 2],
      ]);
      // Messages after a running status still received
      expect(parse([0xB0, 7, 100, 10, 64, 0x90, 60, 100]), [
        [0xB0, 7, 100],
        [0xB0, 10, 64],
        [0x90, 60, 100],
      ]);
    });
    test('real-time inside a message', () {
      // Clock and active sensing between the bytes of a note on.
      expect(parse([0x90, 0xF8, 60, 0xFE, 100]), [
        [0xF8],
        [0xFE],
        [0x90, 60, 100],
      ]);
      // Real-time does not cancel the running status.
      expect(parse([0x90, 60, 100, 0xF8, 62, 100]), [
        [0x90, 60, 100],
        [0xF8],
        [0x90, 62, 100],
      ]);
    });
    test('sysex', () {
      expect(parse([0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]), [
        [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7],
      ]);
      // Clock inside a sysex
      expect(parse([0xF0, 1, 0xF8, 2, 0xF7, 0x90, 60, 100]), [
        [0xF8],
        [0xF0, 1, 2, 0xF7],
        [0x90, 60, 100],
      ]);
    });
    test('system common', () {
      // Song position pointer is 3 bytes, not a sysex.
      expect(parse([0xF2, 0x10, 0x20, 0x90, 60, 100]), [
        [0xF2, 0x10, 0x20],
        [0x90, 60, 100],
      ]);
      expect(parse([0xF1, 5, 0xF3, 2, 0xF6]), [
        [0xF1, 5],
        [0xF3, 2],
        [0xF6],
      ]);
      // A system common message cancels the running status.
      expect(parse([0x90, 60, 100, 0xF6, 62, 100]), [
        [0x90, 60, 100],
        [0xF6],
      ]);
    });
    test('invalid input', () {
      // Data bytes without status, lone end of sysex, undefined status.
      expect(parse([60, 100, 0xF7, 0xF4, 1, 0x90, 60, 100]), [
        [0x90, 60, 100],
      ]);
      // A status byte drops the incomplete message.
      expect(parse([0x90, 60, 0x80, 60, 0]), [
        [0x80, 60, 0],
      ]);
    });
    test('lengthOfMessageType', () {
      expect(lengthOfMessageType(0x90), 3);
      expect(lengthOfMessageType(0xC5), 2);
      expect(lengthOfMessageType(0xF0), -1);
      expect(lengthOfMessageType(0xF2), 3);
      expect(lengthOfMessageType(0xF8), 1);
      expect(lengthOfMessageType(0xF9), 1);
      expect(lengthOfMessageType(0x40), 0);
    });
  });
}
