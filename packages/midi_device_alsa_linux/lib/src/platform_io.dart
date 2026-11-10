import 'package:tekartik_midi_device/midi_device.dart';
import 'package:tekartik_midi_device_alsa_linux/src/device_alsa_linux.dart';

/// The ALSA MIDI device manager (Linux): a new one at each access, read it
/// once.
MidiDeviceManager get midiDeviceManagerAlsaLinux =>
    midiDeviceManagerAlsaLinuxImpl;
