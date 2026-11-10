// ignore_for_file: avoid_print

import 'dart:io';

import 'package:tekartik_midi_device_alsa_linux/midi_device_alsa_linux.dart';

/// Lists the ALSA MIDI devices.
Future<void> main() async {
  if (!Platform.isLinux) {
    stderr.writeln('ALSA MIDI is Linux only');
    return;
  }
  // Read it once: each access builds a new manager.
  final manager = midiDeviceManagerAlsaLinux;
  var devices = await manager.getDevices();
  if (devices.isEmpty) {
    print('No MIDI device (plug a keyboard)');
  }
  for (var device in devices) {
    print(
      '${device.id} ${device.name} '
      'in: ${device.inputPortCount} out: ${device.outputPortCount}',
    );
  }
}
