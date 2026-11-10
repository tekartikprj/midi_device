@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:tekartik_midi_device_alsa_linux/midi_device_alsa_linux.dart';
import 'package:test/test.dart';

void main() {
  test(
    'the public debug switch turns the logs on',
    () async {
      var lines = <String>[];
      midiDeviceManagerAlsaLinuxDebug = true;
      try {
        await runZoned(
          () => midiDeviceManagerAlsaLinux.getDevices(),
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => lines.add(line),
          ),
        );
      } catch (e) {
        markTestSkipped('ALSA not available: $e');
        return;
      } finally {
        midiDeviceManagerAlsaLinuxDebug = false;
      }
      // Was nothing: the implementation read another variable.
      expect(
        lines.where((line) => line.startsWith('ALSA devices:')),
        hasLength(1),
      );
    },
    skip: !Platform.isLinux,
    timeout: const Timeout(Duration(seconds: 20)),
  );
}
