import 'package:tekartik_common_utils/env_utils.dart';
import 'package:tekartik_midi_device_alsa_linux/midi_device_alsa_linux.dart';
import 'package:test/test.dart';

Future<void> main() async {
  test('api', () {
    expect(midiDeviceManagerAlsaLinuxDebug, isFalse);
  });
  test('manager', () async {
    try {
      midiDeviceManagerAlsaLinux;
    } on UnsupportedError catch (_) {
      expect(kDartIsWeb, isTrue);
    }
  });
}
