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
  User? get user => FirebaseAuth.instance.currentUser;

  // --- 1. ฟังก์ชันสร้างโปรเจคใหม่ 
  void _createNewProject() {
    TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("สร้างโปรเจคใหม่"),
        content: TextField(
          controller: nameController,
          maxLength: 20, // เพิ่มบรรทัดนี้: จำกัดจำนวนตัวอักษร และแสดงตัวนับ
          decoration: const InputDecoration(
            hintText: "ชื่อสวน",            
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ยกเลิก"),
          ),
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

  // --- 2. ฟังก์ชันแก้ไขชื่อ 
  void _editProject(String docId, String currentName) {
    TextEditingController nameController = TextEditingController(text: currentName);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("เปลี่ยนชื่อโปรเจค"),
        content: TextField(
          controller: nameController,
          maxLength: 20, // เพิ่มบรรทัดนี้: จำกัดจำนวนตัวอักษร
          decoration: const InputDecoration(hintText: "ชื่อสวนใหม่"),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ยกเลิก"),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                FirebaseFirestore.instance
                    .collection('gardens')
                    .doc(docId)
                    .update({'name': nameController.text});
                
                Navigator.pop(context);
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("เปลี่ยนชื่อเรียบร้อย!")),
                );
              }
            },
            child: const Text("บันทึก"),
          ),
        ],
      ),
    );
  }

  // --- 3. ฟังก์ชันลบโปรเจค ---
  void _deleteProject(String docId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ยืนยันการลบ"),
        content: const Text("ข้อมูลการตรวจทั้งหมดในสวนนี้จะหายไป กู้คืนไม่ได้นะ!"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ยกเลิก"),
          ),
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
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          var docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.eco_outlined, size: 80, color: Colors.grey),
                  SizedBox(height: 10),
                  Text("ยังไม่มีโปรเจค กด + เพื่อสร้างสวนแรกของคุณ"),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var data = docs[index].data();
              String docId = docs[index].id;
              String gardenName = data['name'] ?? "ไม่มีชื่อ";
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.green,
                    child: Icon(Icons.eco, color: Colors.white),
                  ),
                  title: Text(gardenName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("ID: ...${docId.substring(docId.length - 4)}"), 
                  
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.orange),
                        tooltip: "เปลี่ยนชื่อ",
                        onPressed: () => _editProject(docId, gardenName),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        tooltip: "ลบโปรเจค",
                        onPressed: () => _deleteProject(docId),
                      ),
                    ],
                  ),
                  
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => InspectionDatesPage(
                          gardenId: docId, 
                          gardenName: gardenName
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