// lib/ble_service.dart
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  // --- singleton boilerplate ---
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();
  // --------------------------------

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writer;

bool get isConnected => _writer != null;

  /// Start scanning; each event is a **single** ScanResult.
  Stream<ScanResult> scan({Duration timeout = const Duration(seconds: 5)}) {
    FlutterBluePlus.startScan(timeout: timeout);
    // scanResults is Stream<List<ScanResult>>; flatten to Stream<ScanResult>
    return FlutterBluePlus.scanResults.expand((list) => list);
  }

  Future<void> connect(BluetoothDevice d) async {
    await FlutterBluePlus.stopScan();
    _connectedDevice = d;
    await d.connect(timeout: const Duration(seconds: 10), autoConnect: false);
    await _discoverWriter();
  }

  Future<void> stopScan() async {
  await FlutterBluePlus.stopScan();
}


  /// Probe every writable characteristic until one actually accepts a write.
/// This lets us work with *any* ESP32 firmware, no UUID hard‑coding needed.
Future<void> _discoverWriter() async {
  if (_connectedDevice == null) throw Exception('No device');

  final services = await _connectedDevice!.discoverServices();

  for (final s in services) {
    for (final c in s.characteristics) {
      if (!(c.properties.write || c.properties.writeWithoutResponse)) continue;

      // --- try a 1‑byte probe ---
      try {
        final probe = [0x00];

        if (c.properties.write) {
          await c.write(probe, withoutResponse: false);
          _writer = c;
          print('✅ Found writer via write‑with‑response: ${c.uuid}');
          return;
        } else if (c.properties.writeWithoutResponse) {
          await c.write(probe, withoutResponse: true);
          _writer = c;
          print('✅ Found writer via write‑no‑response: ${c.uuid}');
          return;
        }
      } catch (e) {
        // write failed → this char isn’t our guy, keep searching
        print('↩︎  ${c.uuid} rejected probe ($e)');
      }
    }
  }

  throw Exception('No writable characteristic accepted the probe (all gave 0x13)');
}


 Future<void> sendCredentials(String ssid, String pass) async {
  if (_connectedDevice == null) throw Exception('BLE not connected');

  final ssidBytes = utf8.encode(ssid);
  final passBytes = utf8.encode(pass);

  BluetoothCharacteristic? ssidChar;
  BluetoothCharacteristic? passChar;

  // Find SSID and PASS characteristics by partial UUID match
  final services = await _connectedDevice!.discoverServices();
  for (final service in services) {
    for (final c in service.characteristics) {
      final uuid = c.uuid.toString().toLowerCase();
      if (uuid.startsWith('6e400002')) {
        ssidChar = c;
      } else if (uuid.startsWith('6e400003')) {
        passChar = c;
      }
    }
  }

  if (ssidChar == null || passChar == null) {
    throw Exception('SSID or PASS characteristic not found');
  }

  // Write SSID
  await ssidChar.write(ssidBytes, withoutResponse: true);
  await Future.delayed(const Duration(milliseconds: 100)); // slight delay

  // Write PASS
  await passChar.write(passBytes, withoutResponse: true);
  await Future.delayed(const Duration(milliseconds: 100));

  print("[BLE] Credentials sent successfully");
}

  Future<void> disconnect() async {
    await _connectedDevice?.disconnect();
    _connectedDevice = null;
    _writer = null;
  }

}