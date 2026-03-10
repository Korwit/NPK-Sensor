import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class BLEService {
  static final BLEService _instance = BLEService._internal();
  factory BLEService() => _instance;
  BLEService._internal();

  BluetoothDevice? connectedDevice;
  StreamSubscription? _notifySubscription;

  // UUID ต้องตรงกับ ESP32
  final String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String charUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  bool get isConnected => connectedDevice != null && connectedDevice!.isConnected;

  Future<void> connect(BluetoothDevice device) async {
    try {
      await device.connect(autoConnect: false);
      connectedDevice = device;
      await device.discoverServices();

      // subscribe รับค่าจาก ESP32 แบบ NOTIFY แทนการ poll ทุก 10 วิ
      await _subscribeToNPK();
    } catch (e) {
      print('[BLE] Connection Error: $e');
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    await connectedDevice?.disconnect();
    connectedDevice = null;
  }

  // ─── Subscribe รับ NOTIFY จาก ESP32 ───
  // ESP32 จะส่งค่ามาเองทุก 15 วิ (ตาม delay ใน loop)
  // ไม่ต้องให้ Flutter poll เองแล้ว
  Future<void> _subscribeToNPK() async {
    if (!isConnected || connectedDevice == null) return;

    try {
      final services = connectedDevice!.servicesList;

      for (var s in services) {
        if (s.uuid.toString() == serviceUuid) {
          for (var c in s.characteristics) {
            if (c.uuid.toString() == charUuid) {
              // เปิดรับ notification
              await c.setNotifyValue(true);

              // ยกเลิก subscription เก่าก่อนถ้ามี
              await _notifySubscription?.cancel();

              // subscribe รับค่าทุกครั้งที่ ESP32 notify มา
              _notifySubscription = c.lastValueStream.listen((value) async {
                if (value.length < 4) return;

                final int n = value[0];
                final int p = value[1];
                final int k = value[2];
                final int moisture = value[3];

                print('[BLE] รับค่า NOTIFY: N:$n P:$p K:$k Moisture:$moisture');

                // 1. บันทึกลง SharedPreferences (backup กรณี service restart)
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('latest_n', n);
                await prefs.setInt('latest_p', p);
                await prefs.setInt('latest_k', k);
                await prefs.setInt('latest_moisture', moisture);

                // 2. ส่งไป background service ทันที — บันทึก Firestore + GPS
                FlutterBackgroundService().invoke('updateNPK', {
                  'n': n,
                  'p': p,
                  'k': k,
                  'moisture': moisture,
                });
              });

              print('[BLE] Subscribe NOTIFY สำเร็จ รอรับค่าจาก ESP32...');
              return;
            }
          }
        }
      }

      print('[BLE] ไม่พบ Characteristic ที่ตรงกัน');
    } catch (e) {
      print('[BLE] Subscribe Error: $e');
    }
  }

  // ─── อ่านค่าแบบ manual (ใช้ตอนกดปุ่ม "อ่านค่า & บันทึก" ใน HomePage) ───
  Future<Map<String, int>> readNPK() async {
    if (!isConnected || connectedDevice == null) return {};

    try {
      final services = connectedDevice!.servicesList.isEmpty
          ? await connectedDevice!.discoverServices()
          : connectedDevice!.servicesList;

      for (var s in services) {
        if (s.uuid.toString() == serviceUuid) {
          for (var c in s.characteristics) {
            if (c.uuid.toString() == charUuid) {
              final value = await c.read();
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
      print('[BLE] Read Error: $e');
    }
    return {};
  }
}