import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_page.dart';

class InspectionDatesPage extends StatelessWidget {
  final String gardenId;
  final String gardenName;
  final String userRole; // รับ Role มาเช็ค

  const InspectionDatesPage({
    super.key, 
    required this.gardenId, 
    required this.gardenName,
    required this.userRole,
  });

  // --- ฟังก์ชันสร้างวันตรวจใหม่ ---
  void _createNewInspectionDate(BuildContext context) async {
    DateTime now = DateTime.now();
    String dateId = "${now.year}-${now.month}-${now.day}";
    
    await FirebaseFirestore.instance
        .collection('gardens').doc(gardenId)
        .collection('inspections').doc(dateId)
        .set({
          'created_at': FieldValue.serverTimestamp(),
          'display_date': "${now.day}/${now.month}/${now.year + 543}", 
        }, SetOptions(merge: true));

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HomePage(
            gardenId: gardenId,
            inspectionDateId: dateId,
            userRole: userRole,
          ),
        ),
      );
    }
  }

  // --- [เพิ่ม] ฟังก์ชันลบวันตรวจ (เฉพาะ Owner) ---
  void _deleteInspectionDate(BuildContext context, String dateId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ยืนยันการลบ"),
        content: const Text("ประวัติการตรวจของวันนี้จะหายไปทั้งหมด"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ยกเลิก"),
          ),
          TextButton(
            onPressed: () async {
              // ลบเอกสารจาก Firestore
              await FirebaseFirestore.instance
                  .collection('gardens').doc(gardenId)
                  .collection('inspections').doc(dateId)
                  .delete();
              
              if (context.mounted) Navigator.pop(context); // ปิด Dialog
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
    // เช็คสิทธิ์ก่อนเริ่มสร้าง UI
    bool isOwner = (userRole == 'owner');

    return Scaffold(
      appBar: AppBar(
        title: Text("รอบการตรวจ: $gardenName"),
        backgroundColor: Colors.green[700],
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection('gardens').doc(gardenId)
            .collection('inspections')
            .orderBy('created_at', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text("ยังไม่มีรอบการตรวจ กด + เพื่อเริ่มงานวันนี้"));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var data = docs[index].data();
              String dateId = docs[index].id;

              return Card(
                child: ListTile(
                  leading: const Icon(Icons.calendar_today, color: Colors.blue),
                  title: Text("วันที่ตรวจ: ${data['display_date'] ?? dateId}"),
                  subtitle: const Text("แตะเพื่อเข้าไปดูจุดตรวจหรือเพิ่มจุดใหม่"),
                  
                  // [แก้ไข] ส่วนท้าย (Trailing)
                  // ถ้าเป็น Owner: โชว์ปุ่มลบ + ลูกศร
                  // ถ้าเป็น Worker: โชว์แค่ลูกศร
                  trailing: isOwner 
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteInspectionDate(context, dateId),
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 16),
                        ],
                      )
                    : const Icon(Icons.arrow_forward_ios, size: 16),

                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HomePage(
                          gardenId: gardenId,
                          inspectionDateId: dateId,
                          userRole: userRole,
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createNewInspectionDate(context),
        label: const Text("เริ่มตรวจวันนี้"),
        icon: const Icon(Icons.add_task),
        backgroundColor: Colors.green,
      ),
    );
  }
}