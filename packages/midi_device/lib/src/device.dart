/// A Dart interface for MIDI devices, defining the properties and methods
abstract class MidiDevice {
  /// The unique identifier for the MIDI device
  String get id;

  /// The name of the MIDI device
  String get name;

  /// Input port count of the MIDI device
  int get inputPortCount;

  /// Output port count of the MIDI device
  int get outputPortCount;

  /// Debug information about the MIDI device
  Map<String, Object> toDebugMap();
}
