/// The ALSA raw MIDI devices of Linux as a tekartik_midi_device
/// [MidiDeviceManager] ([midiDeviceManagerAlsaLinux]); re-exports the
/// tekartik_midi_device API.
library;

export 'package:tekartik_midi_device/midi_device.dart';
export 'src/device_common.dart'
    show midiDeviceManagerAlsaLinux, midiDeviceManagerAlsaLinuxDebug;
