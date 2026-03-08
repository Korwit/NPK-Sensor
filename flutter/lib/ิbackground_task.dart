import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ฟังก์ชันเตรียมการเบื้องหลัง
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStartBackground,
      autoStart: false, // เราจะสั่งเปิดเองตอนเข้าหน้า HomePage
      isForegroundMode: true, // แจ้งเตือนค้างไว้กัน OS ปิดแอป
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStartBackground,
      onBackground: (ServiceInstance service) => false,
    ),
  );
}

// โค้ดที่จะรันตลอดเวลาแม้อยู่เบื้องหลัง
@pragma('vm:entry-point')
void onStartBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();

  // ดึงค่า ID ที่หน้า UI เซฟไว้ให้
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? gardenId = prefs.getString('bg_gardenId');
  String? inspectionId = prefs.getString('bg_inspectionId');

  if (gardenId == null || inspectionId == null) return;

  int? lastN, lastP, lastK;

  // ดักฟัง Firestore ตลอดเวลา
  FirebaseFirestore.instance
      .collection('ESP01')
      .doc('NPK')
      .snapshots()
      .skip(1) // ไม่เอาค่าแรกสุดตอนเริ่มรัน
      .listen((snapshot) async {
    
    if (snapshot.exists && snapshot.data() != null) {
      var data = snapshot.data() as Map<String, dynamic>;
      int n = data['N'] ?? 0;
      int p = data['P'] ?? 0;
      int k = data['K'] ?? 0;

      // ถ้าค่าซ้ำเดิม ให้ข้ามไป
      if (n == lastN && p == lastP && k == lastK) return;
      lastN = n; lastP = p; lastK = k;

      try {
        // หาพิกัด GPS ปัจจุบัน ณ วินาทีที่ค่าเด้งเข้ามา
        Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);

        // บันทึกลง Firestore
        await FirebaseFirestore.instance
            .collection('gardens').doc(gardenId)
            .collection('inspections').doc(inspectionId)
            .collection('points').add({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': FieldValue.serverTimestamp(),
          'n_value': n, 'p_value': p, 'k_value': k,
          'moisture': 0,
          'source': "ESP32 (Background)",
        });
        print("Background Save Success: N:$n P:$p K:$k");
      } catch (e) {
        print("Background Save Error: $e");
      }
    }
  });

  // รอรับคำสั่งปิดจากหน้า UI
  service.on('stopService').listen((event) {
    service.stopSelf();
  });
}