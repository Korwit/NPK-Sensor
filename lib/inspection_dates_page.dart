import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_page.dart'; // import หน้าแผนที่ (Level 3)

class InspectionDatesPage extends StatelessWidget {
  final String gardenId;
  final String gardenName;

  const InspectionDatesPage({super.key, required this.gardenId, required this.gardenName});

  void _createNewInspectionDate(BuildContext context) async {
    // สร้างชื่อเอกสารเป็น วัน-เดือน-ปี (เช่น 2026-01-31)
    DateTime now = DateTime.now();
    String dateId = "${now.year}-${now.month}-${now.day}";
    
    // สร้างเอกสารวันที่ใน Firestore
    await FirebaseFirestore.instance
        .collection('gardens').doc(gardenId)
        .collection('inspections').doc(dateId)
        .set({
          'created_at': FieldValue.serverTimestamp(),
          'display_date': "${now.day}/${now.month}/${now.year + 543}", // แสดงเป็น พ.ศ.
        }, SetOptions(merge: true));

    // ไปหน้าแผนที่ทันที
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HomePage(
            gardenId: gardenId,
            inspectionDateId: dateId,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    // กดแล้วไปหน้าแผนที่ (Level 3)
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HomePage(
                          gardenId: gardenId,
                          inspectionDateId: dateId,
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