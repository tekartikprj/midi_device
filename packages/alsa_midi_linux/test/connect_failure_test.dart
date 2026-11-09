@TestOn('linux')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:tekartik_alsa_midi_linux/alsa_generated_bindings.dart' as a;
import 'package:tekartik_alsa_midi_linux/midi.dart';
import 'package:test/test.dart';

/// A device that cannot be opened (no rawmidi device 9 on any card), built
/// on the control of the first sound card; null without a sound card (most
/// CI machines).
AlsaMidiDevice? _missingDevice() {
  final card = calloc<Int>()..value = -1;
  final ctl = calloc<Pointer<a.snd_ctl_>>();
  try {
    if (alsa.snd_card_next(card) < 0 || card.value < 0) {
      return null;
    }
    final name = 'hw:${card.value}'.toNativeUtf8().cast<Char>();
    try {
      if (alsa.snd_ctl_open(ctl, name, 0) < 0) {
        return null;
      }
    } finally {
      calloc.free(name);
    }
    try {
      return AlsaMidiDevice(
        ctl.value,
        card.value,
        9,
        'missing',
        'native',
        StreamController<MidiMessage>.broadcast(),
      )..ctl = nullptr;
    } finally {
      alsa.snd_ctl_close(ctl.value);
    }
  } finally {
    calloc.free(card);
    calloc.free(ctl);
  }
}

void main() {
  test('a failed connect keeps no port', () async {
    final device = _missingDevice();
    if (device == null) {
      markTestSkipped('no sound card');
      return;
    }
    expect(await device.connect(), isFalse);
    expect(device.connected, isFalse);
    expect(device.outPort, isNull);
    expect(device.inPort, isNull);
    // No ALSA call on a NULL handle: it used to abort the process.
    device.send(Uint8List.fromList([0x90, 60, 100]));
    device.disconnect();
  });

  test('send frees its buffer', () {
    final device = _missingDevice();
    if (device == null) {
      markTestSkipped('no sound card');
      return;
    }
    // Not connected: nothing is written, the buffer is still allocated.
    final message = Uint8List(2 * 1024 * 1024)
      ..fillRange(0, 2 * 1024 * 1024, 1);
    final before = ProcessInfo.currentRss;
    for (var i = 0; i < 64; i++) {
      device.send(message);
    }
    // 128 MB sent, it used to keep about 128 MB.
    expect(ProcessInfo.currentRss - before, lessThan(32 * 1024 * 1024));
  });
}
