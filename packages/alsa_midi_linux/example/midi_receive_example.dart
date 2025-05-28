// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'package:tekartik_alsa_midi_linux/midi.dart';

void main() async {
  final devices = AlsaMidiDevice.getDevices();

  for (final d in devices) {
    print('found device: ${d.toDictionary}');
  }

  if (devices.isEmpty) {
    print('no midi devices found');
    return;
  }

  // use first device found
  final device = devices.first;

  await device.connect();

  print(
    'connected to: ${device.toDictionary} \n'
    'press q to quit',
  );
  // turn off line mode to get input immediately
  stdin.lineMode = false;
  late StreamSubscription sub;
  sub = stdin.listen((data) {
    if (data.first == 'q'.codeUnitAt(0)) {
      print('disconnecting');
      device.disconnect();
      sub.cancel();
      exit(0);
    }
  });

  // typically ctrl-c in shell will generate a sigint
  ProcessSignal.sigint.watch().listen((signal) {
    print('sigint disconnecting');
    device.disconnect();
    exit(0);
  });

  await device.receivedMessages.forEach((mesg) {
    print('MIDI MESG: ${mesg.toDictionary}');
  });
}
