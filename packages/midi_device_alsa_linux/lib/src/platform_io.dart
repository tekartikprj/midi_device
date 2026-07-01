import 'package:tekartik_midi_device/midi_device.dart';
import 'package:tekartik_midi_device_alsa_linux/src/device_alsa_linux.dart';

/// Midi device manager for ALSA on Linux
MidiDeviceManager get midiDeviceManagerAlsaLinux =>
    midiDeviceManagerAlsaLinuxImpl;
