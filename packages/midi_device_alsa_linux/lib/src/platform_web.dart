import 'package:tekartik_midi_device/midi_device.dart';

/// Not on the web: throws [UnsupportedError].
MidiDeviceManager get midiDeviceManagerAlsaLinux =>
    throw UnsupportedError('Only on linux');
