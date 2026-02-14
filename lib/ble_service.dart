import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';

class BLEService {
  static final BLEService _instance = BLEService._internal();
  factory BLEService() => _instance;
  BLEService._internal();

  BluetoothDevice? connectedDevice;
  
  // UUID ของ Service และ Characteristic (ให้ตรงกับโค้ด ESP32 ของคุณ)
  final String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String charUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  Future<void> connect(BluetoothDevice device) async {
    await device.connect();
    connectedDevice = device;
  }

  void disconnect() {
    connectedDevice?.disconnect();
    connectedDevice = null;
  }

  // ฟังก์ชันอ่านค่าล่าสุดจาก ESP32
  Future<Map<String, int>> readNPK() async {
    if (connectedDevice == null) return {};
    
    List<BluetoothService> services = await connectedDevice!.discoverServices();
    for (var s in services) {
      if (s.uuid.toString() == serviceUuid) {
        for (var c in s.characteristics) {
          if (c.uuid.toString() == charUuid) {
            List<int> value = await c.read();
            // สมมติ ESP32 ส่งมาเป็น [N, P, K, Moisture]
            if (value.length >= 4) {
              return {
                'n': value[0],
                'p': value[1],
                'k': value[2],
                'moisture': value[3],
              };
            }
          }
        }
      }
    }
    return {};
  }
}