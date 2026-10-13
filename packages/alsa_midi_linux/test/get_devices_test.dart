@TestOn('linux')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:tekartik_alsa_midi_linux/alsa_midi_device.dart';
import 'package:test/test.dart';

/// Open file descriptors on /dev/snd (card controls, rawmidi ports).
int _sndFdCount() => Directory('/proc/self/fd').listSync().where((entity) {
  try {
    return Link(entity.path).targetSync().startsWith('/dev/snd/');
  } catch (_) {
    return false;
  }
}).length;

void main() {
  // No MIDI device needed: getDevices opens the control of every sound card
  // (none on most CI machines, the test then checks nothing).
  test('getDevices closes the card controls', () {
    var before = _sndFdCount();
    for (var i = 0; i < 10; i++) {
      var devices = AlsaMidiDevice.getDevices();
      for (var device in devices.where((device) => !device.connected)) {
        expect(device.ctl, nullptr);
      }
    }
    expect(_sndFdCount(), before);
  });
}
