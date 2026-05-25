import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class BluetoothService {
  final _controller = StreamController<String>.broadcast();
  BluetoothConnection? _connection;
  final StringBuffer _buf = StringBuffer();

  Stream<String> get dataStream => _controller.stream;
  bool get isConnected => _connection?.isConnected ?? false;

  Future<bool> scanAndConnect({String nameFilter = 'FarmLink_BT'}) async {
    try {
      await disconnect();

      List<BluetoothDevice> bonded = await FlutterBluetoothSerial.instance
          .getBondedDevices();

      if (kDebugMode) {
        print('[BT] ${bonded.length} paired device(s):');
        for (var d in bonded) print('[BT]   ${d.name} (${d.address})');
      }

      BluetoothDevice? target;

      // 1st pass: exact name match
      for (var d in bonded) {
        if (d.name != null &&
            d.name!.toLowerCase().contains(nameFilter.toLowerCase())) {
          target = d;
          break;
        }
      }
      // 2nd pass: any HC-05
      if (target == null) {
        for (var d in bonded) {
          if (d.name != null &&
              (d.name!.toLowerCase().contains('hc-05') ||
                  d.name!.toLowerCase().contains('hc05') ||
                  d.name!.toLowerCase().contains('farmlink'))) {
            target = d;
            break;
          }
        }
      }
      // 3rd pass: first available
      if (target == null && bonded.isNotEmpty) {
        target = bonded.first;
        if (kDebugMode) print('[BT] Fallback to first device: ${target.name}');
      }

      if (target == null) {
        if (kDebugMode) print('[BT] No device found');
        return false;
      }

      if (kDebugMode) print('[BT] Connecting to ${target.name}...');
      _connection = await BluetoothConnection.toAddress(target.address);
      if (kDebugMode) print('[BT] Connected!');

      _buf.clear();

      _connection!.input!.listen(
        (Uint8List bytes) {
          try {
            _buf.write(utf8.decode(bytes, allowMalformed: true));
            final raw = _buf.toString();
            final lines = raw.split('\n');
            for (int i = 0; i < lines.length - 1; i++) {
              final line = lines[i].replaceAll('\r', '').trim();
              if (line.isNotEmpty) {
                if (kDebugMode) print('[BT] Line: $line');
                _controller.add(line);
              }
            }
            _buf.clear();
            _buf.write(lines.last);
          } catch (e) {
            if (kDebugMode) print('[BT] Decode error: $e');
            _buf.clear();
          }
        },
        onDone: () {
          if (kDebugMode) print('[BT] Disconnected');
          disconnect();
        },
        onError: (e) {
          if (kDebugMode) print('[BT] Error: $e');
          disconnect();
        },
        cancelOnError: false,
      );

      return true;
    } catch (e) {
      if (kDebugMode) print('[BT] Connect error: $e');
      await disconnect();
      return false;
    }
  }

  Future<bool> sendCommand(String cmd) async {
    if (!isConnected) return false;
    try {
      _connection!.output.add(utf8.encode('$cmd\n'));
      await _connection!.output.allSent;
      if (kDebugMode) print('[BT] Sent: $cmd');
      return true;
    } catch (e) {
      if (kDebugMode) print('[BT] Send error: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _connection?.close();
      _connection = null;
      _buf.clear();
    } catch (_) {}
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
