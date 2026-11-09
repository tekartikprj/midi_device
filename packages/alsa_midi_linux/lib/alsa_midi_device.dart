// ignore_for_file: non_constant_identifier_names, avoid_print

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:tekartik_alsa_midi_linux/midi.dart';
import 'package:tuple/tuple.dart';

import 'alsa_generated_bindings.dart' as a;
import 'src/midi_byte_parser.dart';

/// The ALSA bindings, on `libasound.so.2` (opened on first use: Linux only).
final alsa = a.ALSA(DynamicLibrary.open('libasound.so.2'));

final int SND_RAWMIDI_STREAM_INPUT = 1;
final int SND_RAWMIDI_STREAM_OUTPUT = 0;

/// Happens in non-blocking mode when the read buffer is empty
final int SND_ERROR_EAGAIN = -11; // Resource temporarily unavailable

String stringFromNative(Pointer<Char> pointer) {
  return pointer.cast<Utf8>().toDartString();
}

/// Length of the message started by a status byte: 1 to 3, -1 for a sysex,
/// 0 for a data byte or an undefined status.
int lengthOfMessageType(int type) => midiStatusLength(type);

void _rxIsolate(Tuple2<SendPort, int> args) {
  final sendPort = args.item1;
  final Pointer<a.snd_rawmidi_> inPort = Pointer<a.snd_rawmidi_>.fromAddress(
    args.item2,
  );

  //print('start isolate $sendPort, $inPort, ${args.item2}');

  int status = 0;
  //TODO: use a larger buffer than 1 byte, as 1 byte is likely very inefficient
  Pointer<Uint8> buffer = calloc<Uint8>();
  final parser = MidiByteParser();

  // The port is non-blocking, poll its descriptors to wait for data.
  final pollCount = max(alsa.snd_rawmidi_poll_descriptors_count(inPort), 0);
  final pollFds = calloc<a.pollfd>(max(pollCount, 1));
  final pollFdCount = pollCount > 0
      ? alsa.snd_rawmidi_poll_descriptors(inPort, pollFds, pollCount)
      : 0;

  while (true) {
    if ((status = alsa.snd_rawmidi_read(inPort, buffer.cast(), 1)) < 0) {
      if (status == SND_ERROR_EAGAIN) {
        // We have this error in non-blocking mode when the read buffer is empty
        // Wait for data instead of spinning, with a timeout so that the
        // isolate can be killed.
        if (pollFdCount > 0) {
          alsa.poll(pollFds, pollFdCount, 100);
        } else {
          sleep(const Duration(milliseconds: 1));
        }
        continue; // Data available (or timeout), read again
      } else {
        print(
          'Problem reading MIDI input status: $status => ${stringFromNative(alsa.snd_strerror(status))}',
        );
        throw StateError(
          'Problem reading MIDI input: status = $status => ${stringFromNative(alsa.snd_strerror(status))}',
        );
      }
    } else {
      for (var message in parser.add(buffer.value)) {
        sendPort.send(message);
      }
    }
  }
}

/// An ALSA raw MIDI device (`hw:<card>,<device>`), from [getDevices].
///
/// [connect] opens it (input and output) and starts a receive isolate,
/// [send] writes bytes, [receivedMessages] gives the complete messages
/// received, [disconnect] closes it.
class AlsaMidiDevice {
  static final Map<String, AlsaMidiDevice> _connectedDevices =
      <String, AlsaMidiDevice>{};
  static final StreamController<AlsaMidiDevice> _disconnectStreamCtrl =
      StreamController.broadcast();

  /// The devices that [disconnect] closed (a call, or a read error such as
  /// an unplug).
  static Stream<AlsaMidiDevice> get onDeviceDisconnected =>
      _disconnectStreamCtrl.stream.asBroadcastStream();

  /// The output handle once connected, null otherwise.
  Pointer<Pointer<a.snd_rawmidi_>>? outPort;

  /// The input handle once connected, null otherwise.
  Pointer<Pointer<a.snd_rawmidi_>>? inPort;
  final StreamController<MidiMessage> _rxStreamCtrl;
  Isolate? _isolate;

  /// The receive isolate's errors, while connected.
  ReceivePort? errorPort;

  /// The receive isolate's messages, while connected.
  ReceivePort? receivePort;

  /// Card control, only open while [getDevices] enumerates the card
  /// ([nullptr] afterwards).
  Pointer<a.snd_ctl_> ctl;

  /// Always `'native'`.
  String type;

  /// The ALSA card number.
  int cardId;

  /// The raw MIDI device number on the card.
  int deviceId;

  /// Whether [connect] opened it (until [disconnect]).
  bool connected = false;

  /// The card's name (the devices of one card share it).
  String name;

  /// The complete messages received while connected (broadcast). The
  /// devices of one [getDevices] call share this stream: filter on
  /// [MidiMessage.device] when several are connected.
  Stream<MidiMessage> get receivedMessages => _rxStreamCtrl.stream;

  final List<String> _inputPorts = [];
  final List<String> _outputPorts = [];

  /// The input subdevices, `'0'` to `'n-1'`.
  List<String> get inputPorts => _inputPorts;

  /// The output subdevices, `'0'` to `'n-1'`.
  List<String> get outputPorts => _outputPorts;

  /// A device of card [cardId] read through its control [ctl]; use
  /// [getDevices] instead.
  AlsaMidiDevice(
    this.ctl,
    this.cardId,
    this.deviceId,
    this.name,
    this.type,
    this._rxStreamCtrl,
  ) {
    // Fetch device info
    var info = calloc<Pointer<a.snd_rawmidi_info_>>();
    alsa.snd_rawmidi_info_malloc(info);
    try {
      alsa.snd_rawmidi_info_set_device(info.value, deviceId);

      var status = alsa.snd_ctl_rawmidi_info(ctl, info.value);
      if (status < 0) {
        print(
          'error: cannot get device info.value ${alsa.snd_strerror(status).cast<Utf8>().toDartString()}',
        );
        return;
      }

      // Get input ports
      alsa.snd_rawmidi_info_set_stream(info.value, SND_RAWMIDI_STREAM_INPUT);
      status = alsa.snd_ctl_rawmidi_info(ctl, info.value);
      final inCount = alsa.snd_rawmidi_info_get_subdevices_count(info.value);
      for (var i = 0; i < inCount; i++) {
        if (alsa.snd_rawmidi_info_get_subdevice(info.value) < 0) {
          print(
            'error: snd_rawmidi_info_get_subdevice in [$i] $status ${alsa.snd_rawmidi_info_get_subdevice_name(info.value).cast<Utf8>().toDartString()}',
          );
        } else {
          _inputPorts.add('$i');
        }
      }

      // Get output ports
      alsa.snd_rawmidi_info_set_stream(info.value, SND_RAWMIDI_STREAM_OUTPUT);
      status = alsa.snd_ctl_rawmidi_info(ctl, info.value);
      final outCount = alsa.snd_rawmidi_info_get_subdevices_count(info.value);
      for (var i = 0; i < outCount; i++) {
        if (alsa.snd_rawmidi_info_get_subdevice(info.value) < 0) {
          print(
            'error: snd_rawmidi_info_get_subdevice out [$i] $status ${alsa.snd_rawmidi_info_get_subdevice_name(info.value).cast<Utf8>().toDartString()}',
          );
        } else {
          _outputPorts.add('$i');
        }
      }
    } finally {
      if (info.value != nullptr) {
        alsa.snd_rawmidi_info_free(info.value);
      }
      calloc.free(info);
    }
  }

  /// Opens the device (input and output, non-blocking) and starts
  /// receiving: true when connected. False, without throwing, when it
  /// cannot be opened (busy in another program, gone): the device is then
  /// left as it was.
  Future<bool> connect() async {
    // The ports are only kept once open: after a failed open they hold NULL
    // handles, and ALSA aborts the process on a NULL handle (send,
    // disconnect).
    final newOutPort = calloc<Pointer<a.snd_rawmidi_>>();
    final newInPort = calloc<Pointer<a.snd_rawmidi_>>();

    Pointer<Char> name = '${hardwareId(cardId, deviceId)},0'
        .toNativeUtf8()
        .cast<Char>();
    //print('open out port ${stringFromNative(name)}');
    var status = 0;
    try {
      status = alsa.snd_rawmidi_open(
        newInPort,
        newOutPort,
        name,
        a.SND_RAWMIDI_NONBLOCK,
      );
    } finally {
      calloc.free(name);
    }
    if (status < 0) {
      calloc.free(newOutPort);
      calloc.free(newInPort);
      print(
        'error: cannot open card number $cardId ${stringFromNative(alsa.snd_strerror(status))}',
      );
      return false;
    }
    outPort = newOutPort;
    inPort = newInPort;

    connected = true;

    /// Register this device as connected globally
    _connectedDevices[hardwareId(cardId, deviceId)] = this;

    errorPort = ReceivePort();
    receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      _rxIsolate,
      Tuple2(receivePort!.sendPort, inPort!.value.address),
      onError: errorPort!.sendPort,
    );

    errorPort?.listen((message) {
      print('isolate error message $message');
      disconnect();
    });

    receivePort?.listen((data) {
      // print("rx data $data $_rxStreamCtrl ${_rxStreamCtrl.sink}");
      var packet = MidiMessage(
        data as Uint8List,
        DateTime.now().millisecondsSinceEpoch,
        this,
      );
      _rxStreamCtrl.add(packet);
    });

    return true;
  }

  /// Writes [midiMessage] (whole messages, status byte first, e.g.
  /// `[0x90, 60, 100]`). Errors are printed, not thrown (nothing is sent
  /// when not connected). The output is non-blocking: a message longer than
  /// the free space of the ALSA output buffer (4096 bytes by default) is
  /// cut.
  void send(Uint8List midiMessage) {
    final buffer = calloc<Uint8>(midiMessage.lengthInBytes);
    try {
      buffer.asTypedList(midiMessage.length).setAll(0, midiMessage);
      // snd_rawmidi_write copies the bytes: the buffer can go after it.
      _send(buffer, midiMessage.length);
    } finally {
      calloc.free(buffer);
    }
  }

  void _send(Pointer<Uint8> buffer, int length) {
    if (outPort != null) {
      final voidBuffer = buffer.cast<Void>();

      int status;
      if ((status = alsa.snd_rawmidi_write(
            outPort!.value,
            voidBuffer,
            length,
          )) <
          0) {
        print(
          'failed to write ${alsa.snd_strerror(status).cast<Utf8>().toDartString()}',
        );
      }
    } else {
      print('outport is null');
    }
  }

  /// Stops receiving, drains and closes the ports, and emits the device on
  /// [onDeviceDisconnected]. Call it before the program ends (ctrl-C too):
  /// an open device stays busy for the other programs.
  void disconnect() {
    receivePort?.close();
    errorPort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;

    _connectedDevices.remove(hardwareId(cardId, deviceId));
    _disconnectStreamCtrl.add(this);

    var status = 0;
    if (outPort != null) {
      if ((status = alsa.snd_rawmidi_drain(outPort!.value)) < 0) {
        print(
          'error: cannot drain out port $this ${stringFromNative(alsa.snd_strerror(status))}',
        );
      }
      if ((status = alsa.snd_rawmidi_close(outPort!.value)) < 0) {
        print(
          'error: cannot close out port $this ${stringFromNative(alsa.snd_strerror(status))}',
        );
      }
      outPort = null;
    }

    if (inPort != null) {
      if ((status = alsa.snd_rawmidi_drain(inPort!.value)) < 0) {
        print(
          'error: cannot drain in port $this ${stringFromNative(alsa.snd_strerror(status))}',
        );
      }
      if ((status = alsa.snd_rawmidi_close(inPort!.value)) < 0) {
        print(
          'error: cannot close in port $this ${stringFromNative(alsa.snd_strerror(status))}',
        );
      }
      inPort = null;
    }
    connected = false;
  }

  /// `{name, id (the card), type, connected}`, for logs.
  Map<String, Object> get toDictionary {
    return {'name': name, 'id': cardId, 'type': type, 'connected': connected};
  }

  /// The raw MIDI devices of every sound card, the connected ones included
  /// (the same instances). Synchronous; call it again after a plug or an
  /// unplug.
  static List<AlsaMidiDevice> getDevices() {
    StreamController<MidiMessage> rxStreamController =
        StreamController<MidiMessage>.broadcast();
    int status;
    var card = calloc<Int>();
    card.value = -1;

    List<AlsaMidiDevice> devices = [];

    try {
      if ((status = alsa.snd_card_next(card)) < 0) {
        print(
          'error: cannot determine card number ${card.value} ${stringFromNative(alsa.snd_strerror(status))}',
        );
        return [];
      }
      // print('status $status');
      if (card.value < 0) {
        print('error: no sound cards found');
        return [];
      }

      while (card.value >= 0) {
        devices.addAll(_getCardDevices(card.value, rxStreamController));

        // Always move to the next card, even if this one failed.
        if ((status = alsa.snd_card_next(card)) < 0) {
          print(
            'error: cannot determine card number ${card.value} ${stringFromNative(alsa.snd_strerror(status))}',
          );
          break;
        }
      }
    } finally {
      calloc.free(card);
    }

    // Add all connected devices
    devices.addAll(_connectedDevices.values);

    return devices;
  }

  /// The not connected devices of card [cardNumber].
  ///
  /// The card control is only open during the enumeration: [ctl] is then
  /// [nullptr] in the returned devices.
  static List<AlsaMidiDevice> _getCardDevices(
    int cardNumber,
    StreamController<MidiMessage> rxStreamController,
  ) {
    int status;
    List<AlsaMidiDevice> devices = [];
    Pointer<Pointer<Char>> shortname = calloc<Pointer<Char>>();
    Pointer<Char> name = 'hw:$cardNumber'.toNativeUtf8().cast<Char>();
    Pointer<Pointer<a.snd_ctl_>> ctl = calloc<Pointer<a.snd_ctl_>>();
    Pointer<Int> device = calloc<Int>();
    device.value = -1;
    try {
      // print("card $cardNumber");
      if ((status = alsa.snd_card_get_name(cardNumber, shortname)) < 0) {
        print(
          'error: cannot determine card shortname $cardNumber ${stringFromNative(alsa.snd_strerror(status))}',
        );
        return devices;
      }
      // Allocated by ALSA (strdup)
      var cardName = stringFromNative(shortname.value);
      calloc.free(shortname.value);
      // print('name: $cardName');
      status = alsa.snd_ctl_open(ctl, name, 0);
      // print("status after ctl_open $status ctl $ctl ctl.value ${ctl.value}");
      if (status < 0) {
        print(
          'error: cannot open control for card number $cardNumber ${stringFromNative(alsa.snd_strerror(status))}',
        );
        return devices;
      }

      try {
        do {
          status = alsa.snd_ctl_rawmidi_next_device(ctl.value, device);
          // print("status $status device.value ${device.value}");
          if (status < 0) {
            print(
              'error: cannot determine device number ${device.value} ${stringFromNative(alsa.snd_strerror(status))}',
            );
            break;
          }

          if (device.value >= 0) {
            var deviceId = hardwareId(cardNumber, device.value);
            if (!_connectedDevices.containsKey(deviceId)) {
              // print('add unconnected device with id $deviceId');
              devices.add(
                AlsaMidiDevice(
                  ctl.value,
                  cardNumber,
                  device.value,
                  cardName,
                  'native',
                  rxStreamController,
                ),
              );
            }
          }
          // -1 when there is no more device
        } while (device.value >= 0);
      } finally {
        alsa.snd_ctl_close(ctl.value);
        for (var alsaDevice in devices) {
          alsaDevice.ctl = nullptr;
        }
      }
    } finally {
      calloc.free(shortname);
      calloc.free(name);
      calloc.free(ctl);
      calloc.free(device);
    }
    return devices;
  }

  /// The ALSA id of a device, `hw:<card>,<device>`.
  static String hardwareId(int card, int device) => 'hw:$card,$device';
}
