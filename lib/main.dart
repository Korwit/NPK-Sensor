import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_page.dart';
import 'home_page.dart';
import 'projects_page.dart';
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green), // เปลี่ยนเป็นสีเขียวให้เข้ากับธีมตรวจดิน
        useMaterial3: true,
      ),
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

        // หากมีข้อมูล User (ล็อกอินแล้ว) ให้ไปหน้า HomePage
        if (snapshot.hasData) {
          return const ProjectsPage();
        }

        // หากไม่มีข้อมูล User (ยังไม่ล็อกอิน) ให้ไปหน้า LoginPage
        return const LoginPage();
      },
    );
  }
}