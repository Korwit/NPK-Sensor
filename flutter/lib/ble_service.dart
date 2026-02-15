import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';

class BLEService {
  static final BLEService _instance = BLEService._internal();
  factory BLEService() => _instance;
  BLEService._internal();

  BluetoothDevice? connectedDevice;
  
  // UUID ต้องเป็นตัวพิมพ์เล็กทั้งหมดตามมาตรฐาน
  final String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String charUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  // ตรวจสอบสถานะการเชื่อมต่อ
  bool get isConnected => connectedDevice != null && connectedDevice!.isConnected;

  Future<void> connect(BluetoothDevice device) async {
    try {
      await device.connect(autoConnect: false); // autoConnect: false เสถียรกว่าในบางกรณี
      connectedDevice = device;
      
      // ต้อง Discover Services ก่อนถึงจะอ่านค่าได้
      await device.discoverServices(); 
    } catch (e) {
      print("Connection Error: $e");
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await connectedDevice?.disconnect();
    connectedDevice = null;
  }

  // ฟังก์ชันอ่านค่าล่าสุดจาก ESP32
  Future<Map<String, int>> readNPK() async {
    if (!isConnected || connectedDevice == null) return {};
    
    try {
      // ดึง Services ที่ Discover ไว้แล้ว
      List<BluetoothService> services = connectedDevice!.servicesList;
      
      // ถ้ายังไม่มี Services ให้ลอง Discover ใหม่
      if (services.isEmpty) {
        services = await connectedDevice!.discoverServices();
      }

      for (var s in services) {
        if (s.uuid.toString() == serviceUuid) {
          for (var c in s.characteristics) {
            if (c.uuid.toString() == charUuid) {
              // อ่านค่า
              List<int> value = await c.read();
              
              // สมมติ ESP32 ส่งมาเป็น Byte array 4 ตัว [N, P, K, Moisture]
              // หรือถ้าส่งเป็น String ต้องแก้ตรงนี้เพื่อแปลง String เป็น int
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
    } catch (e) {
      print("Read Error: $e");
    }
    return {};
  }
}