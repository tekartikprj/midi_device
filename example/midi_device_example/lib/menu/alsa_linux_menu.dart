import 'dart:typed_data';

import 'package:festenao_common_flutter/common_utils.dart';
import 'package:festenao_common_flutter/dev_menu_flutter.dart';
import 'package:tekartik_midi_device/midi_device.dart';

var deviceIdVar = 'devce_id'.kvFromVar();

void midiDeviceManagerMenu(MidiDeviceManager manager) {
  ConnectedMidiDevice? connectedDevice;
  enter(() async {});
  leave(() async {
    await connectedDevice?.disconnect();
  });
  keyValuesMenu('param', [deviceIdVar]);
  item('list devices', () async {
    var devices = await manager.getDevices();
    if (devices.isEmpty) {
      write('No MIDI devices found.');
    } else {
      write('MIDI Devices:');
      for (var device in devices) {
        write('${device.name} (${device.id})');
      }
    }
  });

  item('Connect to device', () async {
    var deviceId = deviceIdVar.value;
    if (deviceId == null) {
      write('No device id set. Please select a device first.');
      return;
    }

    write('Connected to device: $deviceId');
    var device = await manager.connectDevice(deviceId);
    connectedDevice = device;
    write('Connected to device: $device)');
    device.onMessageReceived.listen((message) {
      write(
        'Received message ${message.timestamp} (${message.device.id}): ${toHexString(message.data)}',
      );
    });
    device.onDisconnected.then((_) {
      write(
        'Device disconnected: ${connectedDevice?.name} (${connectedDevice?.id}',
      );
      connectedDevice = null;
    }).unawait();
  });
  item('Disconnect device', () async {
    var device = connectedDevice;
    if (device == null) {
      write('No device connected.');
      return;
    }
    await device.disconnect();
    write('Disconnect done from device: ${device.name} (${device.id}');
    connectedDevice = null;
  });
  item('Select device id', () async {
    write('Current device id: ${deviceIdVar.value}');
    var devices = await manager.getDevices();
    if (devices.isEmpty) {
      write('No MIDI devices found.');
    } else {
      write('MIDI Devices:');

      await showMenu(() {
        for (var device in devices) {
          item('${device.name} (${device.id})', () async {
            deviceIdVar.set(device.id).unawait();
            write('Selected device: ${device.name} (${device.id})');
            await popMenu();
          });
        }
      });
    }
  });
  Future<void> sendDataMenu(ConnectedMidiDevice device) async {
    await showMenu(() {
      var dataList = [
        [151, 0, 127],
        [151, 0, 0],
      ].map((e) => Uint8List.fromList(e)).toList();
      for (var data in dataList) {
        item('Send data: ${toHexString(data)}', () async {
          try {
            await device.sendData(data);
            write('Data sent: ${data.join(' ')}');
          } catch (e) {
            write('Error sending data: $e');
          }
          await popMenu();
        });
      }
    });
  }

  item('Send data', () async {
    var device = connectedDevice;
    if (device == null) {
      write('No device connected. Please connect to a device first.');
      return;
    }
    await sendDataMenu(device);
  });
  menu('auto connect starlight', () async {
    var service = MidiDeviceService(
      manager: manager,
      select: (device) => device.name.toLowerCase().contains('starlight'),
    );
    enter(() {
      service.start();
      service.onDevice.listen((device) {
        write('Starlight device connected: ${device?.name} (${device?.id})');
      });
      service.onMessage.listen((message) {
        write(
          'Received message ${message.timestamp} (${message.device.id}): ${toHexString(message.data)}',
        );
      });
    });
    leave(() async {
      service.stop();
    });
    item('Send data', () async {
      var device = service.onDevice.value;
      if (device == null) {
        write('No device connected. Please connect to a device first.');
        return;
      }
      await sendDataMenu(device);
    });
  });
}
