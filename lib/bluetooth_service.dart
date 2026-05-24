import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

/// BluetoothService — HC-05 Classic Bluetooth bridge.
///
/// Usage:
///   final bt = BluetoothService();
///   bool ok = await bt.scanAndConnect();
///   bt.dataStream.listen((line) { ... });   // CSV lines from Arduino
///   await bt.sendCommand('1');              // '1' = pump ON, '0' = pump OFF
class BluetoothService {
  final _controller = StreamController<String>.broadcast();
  BluetoothConnection? _connection;

  Stream<String> get dataStream => _controller.stream;
  bool get isConnected => _connection?.isConnected ?? false;

  /// Scans bonded (paired) devices and connects to the first one matching
  /// [nameFilter] (default 'FarmLink_BT', or the old default 'HC-05').
  Future<bool> scanAndConnect({
    Duration timeout = const Duration(seconds: 8),
    String nameFilter = 'FarmLink_BT',
  }) async {
    try {
      await disconnect();

      List<BluetoothDevice> bonded = await FlutterBluetoothSerial.instance
          .getBondedDevices();

      BluetoothDevice? target;
      // Try exact name first, then fall back to 'HC-05'
      for (var d in bonded) {
        if (d.name != null &&
            d.name!.toLowerCase().contains(nameFilter.toLowerCase())) {
          target = d;
          break;
        }
      }
      // Fallback: accept any HC-05 variant
      if (target == null) {
        for (var d in bonded) {
          if (d.name != null && d.name!.toLowerCase().contains('hc-05')) {
            target = d;
            break;
          }
        }
      }

      if (target == null) {
        if (kDebugMode) print('[BT] No matching device found');
        return false;
      }

      if (kDebugMode) print('[BT] Connecting to ${target.name}…');
      _connection = await BluetoothConnection.toAddress(target.address);
      if (kDebugMode) print('[BT] Connected!');

      // Buffer for partial lines
      final StringBuffer _buf = StringBuffer();

      _connection!.input!.listen(
        (Uint8List bytes) {
          try {
            _buf.write(utf8.decode(bytes));
            final raw = _buf.toString();
            final lines = raw.split('\n');
            // All but the last element are complete lines
            for (int i = 0; i < lines.length - 1; i++) {
              final line = lines[i].trim();
              if (line.isNotEmpty) _controller.add(line);
            }
            // Keep the partial last chunk in the buffer
            _buf.clear();
            _buf.write(lines.last);
          } catch (e) {
            if (kDebugMode) print('[BT] Decode error: $e');
          }
        },
        onDone: () {
          if (kDebugMode) print('[BT] Connection closed by device');
          disconnect();
        },
        onError: (e) {
          if (kDebugMode) print('[BT] Stream error: $e');
          disconnect();
        },
      );

      return true;
    } catch (e) {
      if (kDebugMode) print('[BT] Connect error: $e');
      await disconnect();
      return false;
    }
  }

  /// Send a single-character command to the Arduino.
  /// '1' = pump ON (manual override), '0' = pump OFF.
  Future<bool> sendCommand(String text) async {
    if (!isConnected) return false;
    try {
      _connection!.output.add(utf8.encode('$text\n'));
      await _connection!.output.allSent;
      return true;
    } catch (e) {
      if (kDebugMode) print('[BT] Write error: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      _connection?.close();
      _connection = null;
    } catch (_) {}
  }

  void dispose() {
    _controller.close();
    disconnect();
  }
}
