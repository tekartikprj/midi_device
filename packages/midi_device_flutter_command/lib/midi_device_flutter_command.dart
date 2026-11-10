/// The MIDI devices of the flutter_midi_command plugin as a
/// tekartik_midi_device [MidiDeviceManager]
/// ([midiDeviceManagerFlutterCommand]); re-exports the tekartik_midi_device
/// API.
library;

export 'package:tekartik_midi_device/midi_device.dart';
export 'src/device_flutter_command.dart'
    show midiDeviceManagerFlutterCommand, midiDeviceManagerFlutterCommandDebug;
