// ignore_for_file: avoid_print

@TestOn('vm')
library;

import 'dart:io';

import 'package:tekartik_midi_device_alsa_linux/midi_device_alsa_linux.dart';
import 'package:test/test.dart';

Future<void> main() async {
  var isLinux = Platform.isLinux;
  group('linux io', () {
    test('manager', () async {
      var manager = midiDeviceManagerAlsaLinux;
      try {
        var devices = await manager.getDevices();
        print('Devices: ${devices.length}');
        for (var device in devices) {
          print(device);
        }
      } catch (e) {
        print('Error getting devices: $e');
      }
    });
  }, skip: !isLinux);
}
