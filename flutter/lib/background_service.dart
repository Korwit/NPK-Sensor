import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
// ❌ ลบ import ble_service.dart ออก — BLEService ใช้ใน background isolate ไม่ได้
// import 'ble_service.dart';

// ─────────────────────────────────────────────
// 1. Initialize Service
// ─────────────────────────────────────────────
Future<void> initializeService() async {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'npk_tracking',
    'ระบบบันทึก NPK อัตโนมัติ',
    description: 'Background service สำหรับบันทึกค่าดิน NPK และพิกัด GPS',
    importance: Importance.low,
  );

  await FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'npk_tracking',
      initialNotificationTitle: 'ระบบบันทึก NPK อัตโนมัติ',
      initialNotificationContent: 'กำลังรอรับค่าจากเซนเซอร์...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

// ─────────────────────────────────────────────
// 2. iOS Background Handler
// ─────────────────────────────────────────────
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// ─────────────────────────────────────────────
// 3. Main Background Entry Point
// ─────────────────────────────────────────────
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? gardenId  = prefs.getString('bg_garden_id');
  String? inspectId = prefs.getString('bg_inspect_id');

  // ─── Android Foreground Controls ───
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  // ─── Stop Service ───
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // ─── รับ gardenId / inspectId จาก UI ───
  service.on('updateIds').listen((event) async {
    if (event != null) {
      prefs     = await SharedPreferences.getInstance();
      gardenId  = event['garden_id'] as String?;
      inspectId = event['inspect_id'] as String?;
      if (gardenId  != null) await prefs.setString('bg_garden_id', gardenId!);
      if (inspectId != null) await prefs.setString('bg_inspect_id', inspectId!);
      debugPrint('[BG] อัปเดต IDs: garden=$gardenId inspect=$inspectId');
    }
  });

  // ─── รับค่า NPK แล้วบันทึก + ส่ง ACK กลับ ESP32 ───
  service.on('updateNPK').listen((event) async {
    if (event == null) return;

    final int n        = event['n']        ?? 0;
    final int p        = event['p']        ?? 0;
    final int k        = event['k']        ?? 0;
    final int moisture = event['moisture'] ?? 0;

    debugPrint('[BG] รับค่า NPK: N:$n P:$p K:$k Moisture:$moisture');

    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: 'รับค่าจากเซนเซอร์แล้ว — กำลังบันทึก...',
          content: 'N:$n P:$p K:$k Moisture:$moisture%',
        );
      }
    }

    final currentGardenId  = gardenId  ?? prefs.getString('bg_garden_id');
    final currentInspectId = inspectId ?? prefs.getString('bg_inspect_id');

    if (currentGardenId == null || currentInspectId == null) {
      debugPrint('[BG] ยังไม่มี gardenId หรือ inspectId — ข้ามรอบนี้');
      return;
    }

    try {
      // ดึง GPS
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // บันทึกลง Firestore
      await FirebaseFirestore.instance
          .collection('gardens').doc(currentGardenId)
          .collection('inspections').doc(currentInspectId)
          .collection('points')
          .add({
        'latitude':  position.latitude,
        'longitude': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'n_value':   n,
        'p_value':   p,
        'k_value':   k,
        'moisture':  moisture,
        'source':    'Auto (BLE)',
      });

      debugPrint('[BG] บันทึกสำเร็จ @ (${position.latitude}, ${position.longitude})');

      // ✅ แก้ไข: ส่ง event กลับ UI isolate เพื่อให้ UI เป็นคน writeAck()
      // เหตุผล: BLEService singleton ไม่ share ข้าม isolate
      // connectedDevice ใน background จะเป็น null เสมอ
      service.invoke('sendAckToBLE', {});
      debugPrint('[BG] invoke sendAckToBLE → UI isolate แล้ว');

      // อัปเดต notification
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          service.setForegroundNotificationInfo(
            title: 'บันทึกสำเร็จ ✓',
            content:
                'N:$n P:$p K:$k | ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')} น.',
          );
        }
      }

      // ส่ง event กลับ UI (แสดงผลในแอป)
      service.invoke('onDataSaved', {
        'latitude':  position.latitude,
        'longitude': position.longitude,
        'n': n, 'p': p, 'k': k,
        'timestamp': DateTime.now().toIso8601String(),
      });

    } catch (e) {
      debugPrint('[BG] Error: $e');

      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          service.setForegroundNotificationInfo(
            title: 'เกิดข้อผิดพลาด',
            content: 'บันทึกไม่สำเร็จ: $e',
          );
        }
      }
    }
  });
}