import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'inspection_dates_page.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  // เรียก user ใน build เพื่อให้ได้ค่าที่อัปเดตเสมอ
  User? get user => FirebaseAuth.instance.currentUser;

  void _createNewProject() {
    TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("สร้างโปรเจคใหม่"),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: "ชื่อสวน"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ยกเลิก")),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                FirebaseFirestore.instance.collection('gardens').add({
                  'name': nameController.text,
                  'owner_uid': user?.uid,
                  'created_at': FieldValue.serverTimestamp(),
                });
                Navigator.pop(context);
              }
            },
            child: const Text("สร้าง"),
          ),
        ],
      ),
    );
  }

  void _deleteProject(String docId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ยืนยันการลบ"),
        content: const Text("ข้อมูลทั้งหมดในสวนนี้จะหายไป"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ยกเลิก")),
          TextButton(
            onPressed: () {
              FirebaseFirestore.instance.collection('gardens').doc(docId).delete();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("ลบ"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("เลือกโปรเจคสวน"),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          )
        ],
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection('gardens')
            .where('owner_uid', isEqualTo: user?.uid)
            .orderBy('created_at', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          // 1. เช็ค Error ก่อน (สำคัญมาก เพื่อแก้ปัญหาหมุนค้าง)
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 50),
                    const SizedBox(height: 10),
                    const Text("เกิดข้อผิดพลาดฐานข้อมูล", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    // แสดงข้อความ Error จริงออกมา
                    Text(snapshot.error.toString(), textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    const Text(
                      "วิธีแก้: ดูที่ Debug Console แล้วคลิกลิงก์ 'Create Index'",
                      style: TextStyle(color: Colors.blue),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          // 2. เช็คสถานะโหลดปกติ
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          var docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text("ยังไม่มีโปรเจค กด + เพื่อสร้าง"));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var data = docs[index].data();
              String docId = docs[index].id;
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: const Icon(Icons.eco, color: Colors.green, size: 40),
                  title: Text(data['name'] ?? "ไม่มีชื่อ", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("ID: $docId"),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteProject(docId),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => InspectionDatesPage(
                          gardenId: docId, 
                          gardenName: data['name']
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewProject,
        backgroundColor: Colors.green,
        child: const Icon(Icons.add),
      ),
    );
  }
}