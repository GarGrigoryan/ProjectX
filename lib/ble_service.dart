import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';



class BleService {
  BleService._privateConstructor();
  static final BleService instance = BleService._privateConstructor();

  final FlutterBluePlus _ble = FlutterBluePlus.instance();

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  List<ScanResult> _scanResults = [];

  List<ScanResult> get scanResults => _scanResults;

  Stream<List<ScanResult>> scan({Duration timeout = const Duration(seconds: 5)}) {
    _scanResults = [];
    return _ble.scan(timeout: timeout).map((scanResult) {
      _scanResults.add(scanResult);
      return _scanResults;
    });
  }

  Future<void> stopScan() async {
    await _ble.stopScan();
    _scanSubscription?.cancel();
  }

  Future<void> connect(BluetoothDevice device) async {
    _connectedDevice = device;
    await device.connect();
    List<BluetoothService> services = await device.discoverServices();
    for (var service in services) {
      if (service.uuid == _serviceUuid) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid == _writeUuid) {
            _writeCharacteristic = characteristic;
            break;
          }
        }
      }
    }
  }

  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
      _writeCharacteristic = null;
    }
  }

  bool get isConnected {
    if (_connectedDevice == null) return false;
    return _connectedDevice!.state == BluetoothDeviceState.connected;
  }

  Future<void> sendData(List<int> data) async {
    if (_writeCharacteristic == null) {
      throw Exception('No writable characteristic found!');
    }
    await _writeCharacteristic!.write(data, withoutResponse: true);
  }

  Future<void> sendCredentials(String ssid, String password) async {
    final data = <int>[];
    data.addAll(ssid.codeUnits);
    data.add(0); // null separator
    data.addAll(password.codeUnits);
    await sendData(data);
  }
}
