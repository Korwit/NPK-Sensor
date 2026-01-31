import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // [เพิ่ม] Import Firestore
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserEmail();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _emailController.text = prefs.getString('remembered_email') ?? '';
        _rememberMe = prefs.getBool('remember_me') ?? false;
      });
    }
  }

  Future<void> _handleRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('remembered_email', _emailController.text.trim());
      await prefs.setBool('remember_me', true);
    } else {
      await prefs.remove('remembered_email');
      await prefs.setBool('remember_me', false);
    }
  }

  Future<void> signIn() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("กรุณากรอกข้อมูลให้ครบถ้วน")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. สั่งล็อกอินกับ Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // --- [Step 1: เพิ่มโค้ดส่วนนี้] ---
      // บันทึกข้อมูลลงสมุดหน้าเหลือง (Users Collection) เพื่อให้เพื่อนค้นหาเจอ
      if (userCredential.user != null) {
        await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
          'uid': userCredential.user!.uid,
          'email': userCredential.user!.email,
          'last_login': FieldValue.serverTimestamp(), // เก็บเวลาล่าสุดที่เข้าใช้งาน
        }, SetOptions(merge: true)); // merge: true แปลว่าถ้ามีอยู่แล้วให้อัปเดต ไม่ทับข้อมูลเดิม
      }
      // -------------------------------

      await _handleRememberMe();

      // ไม่ต้องสั่งเปลี่ยนหน้าเอง AuthGate จัดการให้
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String errorMessage = "อีเมลหรือรหัสผ่านไม่ถูกต้อง";
        if (e.code == 'user-not-found') errorMessage = "ไม่พบผู้ใช้งานนี้";
        if (e.code == 'wrong-password') errorMessage = "รหัสผ่านไม่ถูกต้อง";

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("เกิดข้อผิดพลาด: ${e.toString()}")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> resetPassword() async {
    final email = _emailController.text.trim();
    
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("กรุณากรอกอีเมลก่อนกดลืมรหัสผ่าน")),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("ตรวจสอบอีเมลของคุณ"),
            content: Text("ระบบได้ส่งลิงก์สำหรับตั้งรหัสผ่านใหม่ไปที่ $email เรียบร้อยแล้ว"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("ตกลง"),
              ),
            ],
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String message = "เกิดข้อผิดพลาด";
        if (e.code == 'user-not-found') {
          message = "ไม่พบอีเมลนี้ในระบบ";
        } else if (e.code == 'invalid-email') {
          message = "รูปแบบอีเมลไม่ถูกต้อง";
        } else {
          message = e.message ?? "ไม่สามารถส่งอีเมลได้";
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ระบบตรวจวัดคุณภาพดิน - Login")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 50),
              const Icon(Icons.eco, size: 100, color: Colors.green),
              const SizedBox(height: 30),

              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 15),

              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
              ),

              Row(
                children: [
                  Checkbox(
                    value: _rememberMe,
                    onChanged: (value) {
                      setState(() {
                        _rememberMe = value ?? false;
                      });
                    },
                  ),
                  const Text("จดจำอีเมล"),
                  const Spacer(),
                  TextButton(
                    onPressed: resetPassword,
                    child: const Text(
                      "ลืมรหัสผ่าน?",
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : signIn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "เข้าสู่ระบบ",
                          style: TextStyle(fontSize: 18),
                        ),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RegisterPage(),
                    ),
                  );
                },
                child: const Text("ยังไม่มีบัญชี? สมัครสมาชิกที่นี่"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}