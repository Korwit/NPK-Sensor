import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb; 
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';

import 'firebase_options.dart';
import 'login_page.dart';
import 'projects_page.dart';

// ----------------------------------------------------------------------
// ส่วนที่ 1: ตั้งค่า Background Service (สำหรับมือถือเท่านั้น)
// ----------------------------------------------------------------------
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStartBackground,
      autoStart: false, 
      isForegroundMode: true, 
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStartBackground,
      onBackground: (ServiceInstance service) => false,
    ),
  );
}

// ฟังก์ชันที่จะทำงานตลอดเวลาแม้อยู่เบื้องหลัง (ห้ามลบ @pragma)
@pragma('vm:entry-point')
void onStartBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? gardenId = prefs.getString('bg_gardenId');
  String? inspectionId = prefs.getString('bg_inspectionId');

  if (gardenId == null || inspectionId == null) return;

  bool isFirstLoad = true; // [สำคัญ] เช็กว่าเพิ่งเปิดแอปหรือไม่ เพื่อกันเซฟค่าเก่า
  int? lastN, lastP, lastK;

  // ดักฟัง Firestore อัตโนมัติ (ESP01/NPK)
  FirebaseFirestore.instance
      .collection('ESP01')
      .doc('NPK')
      .snapshots()
      .listen((snapshot) async {
    
    if (snapshot.exists && snapshot.data() != null) {
      var data = snapshot.data() as Map<String, dynamic>;
      int n = data['N'] ?? 0;
      int p = data['P'] ?? 0;
      int k = data['K'] ?? 0;

      // 1. ถ้าเป็นการโหลดครั้งแรก ให้จำค่าไว้ แต่ห้ามบันทึก
      if (isFirstLoad) {
        isFirstLoad = false;
        lastN = n; lastP = p; lastK = k;
        return; 
      }

      // 2. ถ้าค่าซ้ำเดิม ให้ข้ามการบันทึก (กันเซฟซ้ำซ้อน)
      if (n == lastN && p == lastP && k == lastK) return;
      
      lastN = n; lastP = p; lastK = k;

      try {
        // 3. ดึง GPS และเวลาปัจจุบันของเครื่อง ณ วินาทีที่ค่าเปลี่ยน
        Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        DateTime currentTime = DateTime.now();

        await FirebaseFirestore.instance
            .collection('gardens').doc(gardenId)
            .collection('inspections').doc(inspectionId)
            .collection('points').add({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': Timestamp.fromDate(currentTime), // ใช้เวลาเครื่องให้เป๊ะที่สุด
          'n_value': n, 'p_value': p, 'k_value': k,
          'moisture': 0, 
          'source': "ESP32 (Mobile-Auto)",
        });
        debugPrint("Background Save Success at $currentTime (N:$n P:$p K:$k)");
      } catch (e) {
        debugPrint("Background Save Error: $e");
      }
    }
  });

  // รอรับคำสั่งปิดจากหน้า UI
  service.on('stopService').listen((event) {
    service.stopSelf();
  });
}

// ----------------------------------------------------------------------
// ส่วนที่ 2: ตั้งค่าตัวแอปหลัก (Main App)
// ----------------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // รันระบบตั้งค่าเบื้องหลัง เฉพาะเมื่อไม่ได้เปิดบน Web
  if (!kIsWeb) {
    await initializeBackgroundService(); 
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ระบบตรวจคุณภาพวัดดิน',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('th', 'TH'),
      ],
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return const ProjectsPage();
        }
        return const LoginPage();
      },
    );
  }
}