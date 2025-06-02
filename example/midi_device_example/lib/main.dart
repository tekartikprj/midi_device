import 'dart:io';

import 'package:festenao_common_flutter/dev_menu_flutter.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:tekartik_midi_device_alsa_linux/midi_device_alsa_linux.dart';
import 'package:tekartik_midi_device_example/menu/alsa_linux_menu.dart';
import 'package:tekartik_midi_device_flutter_command/midi_device_flutter_command.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  mainMenuFlutter(appMenu, showConsole: true);
}

void appMenu() {
  midiDeviceManagerAlsaLinuxDebug = true;
  midiDeviceManagerFlutterCommandDebug = true;
  if (!kIsWeb && Platform.isLinux) {
    menu('alsa linux', () {
      midiDeviceManagerMenu(midiDeviceManagerAlsaLinux);
    });
  }
  menu('flutter_command', () {
    midiDeviceManagerMenu(midiDeviceManagerFlutterCommand);
  });
}
