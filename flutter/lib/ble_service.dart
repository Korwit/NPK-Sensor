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

  bool _isManualReading = false;

  // ✅ ตัวแปรระดับ Global อยู่ตลอดการเปิดแอป
  Map<String, int>? _lastSavedData;

  final String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String charUuid    = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  final String ackUuid     = "beb5483e-36e1-4688-b7f5-ea07361b26a9";

  bool get isConnected => connectedDevice != null && connectedDevice!.isConnected;

  // ✅ ฟังก์ชันสำหรับจำค่าเมื่อกดบันทึกลง Firebase สำเร็จ
  void markAsSaved(int n, int p, int k, int m) {
    _lastSavedData = {'n': n, 'p': p, 'k': k, 'moisture': m};
  }


  Future<void> connect(BluetoothDevice device) async {
    try {
      // ✅ ตั้งเวลา Timeout 5 วินาที
      await device.connect(autoConnect: false).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          device.disconnect(); // สั่งยกเลิกการเชื่อมต่อที่ค้างอยู่ในระบบเครื่อง
          throw Exception("Timeout"); // โยน Error ออกไป
        },
      );
      
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

                if (_isManualReading) {
                  print('[BLE] skip background invoke — manual reading');
                  return;
                }

                final int n        = value[0];
                final int p        = value[1];
                final int k        = value[2];
                final int moisture = value[3];

                // ✅ ดักจับค่า 0: ถ้า ESP32 ส่งค่า 0 มา (เพราะเพิ่งล้าง Buffer) ให้ข้ามการทำงานไปเลย ห้ามเซฟ!
                if (n == 0 && p == 0 && k == 0) {
                  print('[BLE] ได้รับก้อนข้อมูลว่าง (0,0,0) จากการเคลียร์ Buffer -> ข้ามการบันทึก');
                  return; 
                }

                print('[BLE] รับค่า NOTIFY: N:$n P:$p K:$k Moisture:$moisture');

                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('latest_n', n);
                await prefs.setInt('latest_p', p);
                await prefs.setInt('latest_k', k);
                await prefs.setInt('latest_moisture', moisture);

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

  Future<void> writeAck() async {
    print('[ACK] writeAck() called');
    
    if (!isConnected || connectedDevice == null) {
      print('[ACK] ❌ return early — not connected');
      return;
    }

    try {
      for (var s in connectedDevice!.servicesList) {
        for (var c in s.characteristics) {
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

  Future<Map<String, int>> readNPK() async {
    if (!isConnected || connectedDevice == null) return {};

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
                int n = value[0];
                int p = value[1];
                int k = value[2];
                int moist = value[3];

                // ✅ เช็กข้อมูลซ้ำ (Stale Data Guard)
                if (_lastSavedData != null &&
                    n == _lastSavedData!['n'] &&
                    p == _lastSavedData!['p'] &&
                    k == _lastSavedData!['k'] &&
                    moist == _lastSavedData!['moisture']) {
                  
                  return {'n': 0, 'p': 0, 'k': 0, 'moisture': 0, 'isStale': 1};
                }

                return {
                  'n': n,
                  'p': p,
                  'k': k,
                  'moisture': moist,
                  'isStale': 0
                };
              }
            }
          }
        }
      }
    } catch (e) {
      print('[BLE] Read Error: $e');
    } finally {
      _isManualReading = false;
    }

    return {};
  }
}