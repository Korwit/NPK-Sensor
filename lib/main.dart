import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
// [สำคัญ] ต้อง import localization เพื่อรองรับภาษาไทย
import 'package:flutter_localizations/flutter_localizations.dart'; 

import 'login_page.dart';
import 'projects_page.dart'; // ใช้ ProjectsPage เป็นหน้าแรกหลัง Login

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // ปิดแถบ Debug
      title: 'ระบบตรวจคุณภาพวัดดิน',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green), // ธีมสีเขียว
        useMaterial3: true,
      ),
      
      // --- [ส่วนที่เพิ่ม] ตั้งค่าภาษาไทย ---
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('th', 'TH'), // บังคับให้แอปใช้ภาษาไทย (ปฏิทินจะเป็น พ.ศ. อัตโนมัติ)
      ],
      // ----------------------------------

      // ใช้ StreamBuilder เพื่อดักฟังสถานะการ Login
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      // ดักฟังการเปลี่ยนแปลงสถานะ Auth (Login/Logout)
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // หากกำลังโหลดข้อมูล
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // หากมีข้อมูล User (ล็อกอินแล้ว) ให้ไปหน้าเลือกโปรเจค (ProjectsPage)
        if (snapshot.hasData) {
          return const ProjectsPage();
        }

        // หากไม่มีข้อมูล User (ยังไม่ล็อกอิน) ให้ไปหน้า LoginPage
        return const LoginPage();
      },
    );
  }
}