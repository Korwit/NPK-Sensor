import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // ตัวแปรสำหรับเช็คเงื่อนไขรหัสผ่านแบบ Real-time
  bool _isPasswordSixCharacters = false;


  // ฟังก์ชันเช็ครหัสผ่านขณะพิมพ์
  void onPasswordChanged(String password) {
    setState(() {
      _isPasswordSixCharacters = password.length >= 6;

    });
  }

  // ฟังก์ชันสมัครสมาชิก
  Future signUp() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    // 1. ตรวจสอบช่องว่าง
    if (email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showErrorDialog("กรุณากรอกข้อมูลให้ครบทุกช่อง");
      return;
    }

    // 2. ตรวจสอบภาษาไทยใน Email
    if (RegExp(r'[ก-๙]').hasMatch(email)) {
      _showErrorDialog("อีเมลต้องไม่มีตัวอักษรภาษาไทย");
      return;
    }

    // 3. ตรวจสอบรูปแบบ Email
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      _showErrorDialog("รูปแบบอีเมลไม่ถูกต้อง");
      return;
    }

    // 4. ตรวจสอบเงื่อนไขรหัสผ่าน (Checklist)
    if (!_isPasswordSixCharacters) {
      _showErrorDialog("รหัสผ่านยังไม่ครบตามเงื่อนไข");
      return;
    }

    // 5. ตรวจสอบรหัสผ่านตรงกัน
    if (password != confirmPassword) {
      _showErrorDialog("รหัสผ่านไม่ตรงกัน");
      return;
    }

    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await FirebaseAuth.instance.signOut();

      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("สมัครสมาชิกสำเร็จ"),
            content: const Text("กรุณาเข้าสู่ระบบอีกครั้ง"),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // ปิด Dialog
                  Navigator.pop(context); // กลับหน้า Login
                },
                child: const Text("ตกลง"),
              ),
            ],
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = "เกิดข้อผิดพลาด";
      if (e.code == 'email-already-in-use') {
        message = "อีเมลนี้ถูกใช้งานไปแล้ว";
      }
      _showErrorDialog(message);
    } catch (e) {
      _showErrorDialog("Error: ${e.toString()}");
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("สมัครสมาชิกไม่สำเร็จ"),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ตกลง")),
        ],
      ),
    );
  }

  // Widget สำหรับรายการเช็คลิสต์รหัสผ่าน
  Widget buildCheckItem(String title, bool isReady) {
    return Row(
      children: [
        Icon(
          isReady ? Icons.check_circle : Icons.cancel,
          color: isReady ? Colors.green : Colors.grey,
          size: 20,
        ),
        const SizedBox(width: 10),
        Text(title, style: TextStyle(color: isReady ? Colors.black : Colors.grey)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("สมัครใช้งาน")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: Icon(Icons.person_add, size: 80, color: Colors.green)),
              const SizedBox(height: 20),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _passwordController,
                obscureText: true,
                onChanged: onPasswordChanged,
                decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              // --- เพิ่มเงื่อนไข: ถ้ายังติ๊กไม่ครบ 3 อัน ให้แสดงรายการเช็คลิสต์ ---
              if (!(_isPasswordSixCharacters )) ...[
                buildCheckItem("มีอย่างน้อย 6 ตัวอักษร", _isPasswordSixCharacters),
              ] else ...[
                // ถ้าครบแล้ว แสดงข้อความบอกว่ารหัสผ่านปลอดภัย
                const Padding(
                  padding: EdgeInsets.only(left: 4.0),
                  child: Text("", style: TextStyle(color: Colors.green, fontSize: 12)),
                ),
              ],
              const SizedBox(height: 15),
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                onChanged: (value) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Confirm Password', border: OutlineInputBorder()),
              ),
              if (_confirmPasswordController.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    _passwordController.text == _confirmPasswordController.text ? "✓ รหัสผ่านตรงกัน" : "✗ รหัสผ่านไม่ตรงกัน",
                    style: TextStyle(
                      color: _passwordController.text == _confirmPasswordController.text ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: signUp,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  child: const Text("สมัครสมาชิก"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}