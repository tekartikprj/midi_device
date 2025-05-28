import 'package:festenao_common_flutter/dev_menu_flutter.dart';
import 'package:tekartik_midi_device_alsa_linux/midi_device_alsa_linux.dart';
import 'package:tekartik_midi_device_example/menu/alsa_linux_menu.dart';

Future<void> main(List<String> args) async {
  mainMenuFlutter(appMenu, showConsole: true);
}

void appMenu() {
  midiDeviceManagerAlsaLinuxDebug = true;
  midiDeviceManagerMenu(midiDeviceManagerAlsaLinux);
}
