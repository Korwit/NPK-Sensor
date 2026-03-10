import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

class BLEService {
  static final BLEService _instance = BLEService._internal();
  factory BLEService() => _instance;
  BLEService._internal();

  BluetoothDevice? connectedDevice;
  StreamSubscription? _notifySubscription;

  // ✅ flag กัน double save — set true ตอน readNPK() (manual) เพื่อ skip background invoke
  bool _isManualReading = false;

  final String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String charUuid    = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  final String ackUuid     = "beb5483e-36e1-4688-b7f5-ea07361b26a9";

  bool get isConnected => connectedDevice != null && connectedDevice!.isConnected;

  Future<void> connect(BluetoothDevice device) async {
    try {
      await device.connect(autoConnect: false);
      connectedDevice = device;
      await device.discoverServices();
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
  Future<void> _subscribeToNPK() async {
    if (!isConnected || connectedDevice == null) return;

    try {
      for (var s in connectedDevice!.servicesList) {
        if (s.uuid.toString() == serviceUuid) {
          for (var c in s.characteristics) {
            if (c.uuid.toString() == charUuid) {
              await c.setNotifyValue(true);
              await _notifySubscription?.cancel();

              _notifySubscription = c.lastValueStream.listen((value) async {
                if (value.length < 4) return;

                // ✅ ถ้ากำลัง manual read อยู่ ให้ข้ามเพื่อกัน double save
                if (_isManualReading) {
                  print('[BLE] skip background invoke — manual reading');
                  return;
                }

                final int n        = value[0];
                final int p        = value[1];
                final int k        = value[2];
                final int moisture = value[3];

                print('[BLE] รับค่า NOTIFY: N:$n P:$p K:$k Moisture:$moisture');

                // บันทึกลง SharedPreferences
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('latest_n', n);
                await prefs.setInt('latest_p', p);
                await prefs.setInt('latest_k', k);
                await prefs.setInt('latest_moisture', moisture);

                // ส่งไป background service — บันทึก Firestore + GPS
                FlutterBackgroundService().invoke('updateNPK', {
                  'n': n, 'p': p, 'k': k, 'moisture': moisture,
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

  // ─── ส่ง ACK "OK" กลับไป ESP32 หลังบันทึก Firestore สำเร็จ ───
Future<void> writeAck() async {
  print('[ACK] writeAck() called');
  print('[ACK] isConnected: $isConnected');
  print('[ACK] connectedDevice: $connectedDevice');
  
  if (!isConnected || connectedDevice == null) {
    print('[ACK] ❌ return early — not connected');
    return;
  }

  try {
    print('[ACK] servicesList count: ${connectedDevice!.servicesList.length}');
    for (var s in connectedDevice!.servicesList) {
      print('[ACK] service: ${s.uuid}');
      for (var c in s.characteristics) {
        print('[ACK]   char: ${c.uuid}');
        if (c.uuid.toString() == ackUuid) {
          print('[ACK] ✅ found ACK char — writing OK...');
          await c.write(utf8.encode("OK"), withoutResponse: false);
          print('[ACK] ✅ write done');
          return;
        }
      }
    }
    print('[ACK] ❌ ACK Characteristic ไม่พบ');
  } catch (e) {
    print('[ACK] ❌ Error: $e');
  }
}

  // ─── อ่านค่าแบบ manual (กดปุ่มในแอป) ───
  Future<Map<String, int>> readNPK() async {
    if (!isConnected || connectedDevice == null) return {};

    // ✅ set flag ก่อน read เพื่อกัน lastValueStream invoke background ซ้ำ
    _isManualReading = true;

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
    } finally {
      // ✅ clear flag เสมอ ไม่ว่าจะสำเร็จหรือ error
      _isManualReading = false;
    }

    return {};
  }
}