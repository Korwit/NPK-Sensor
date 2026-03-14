import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
// หมายเหตุ: หากต้องการให้ดาวน์โหลดบน iOS ได้ด้วย ต้องติดตั้งแพ็กเกจ path_provider เพิ่มเติม
// แต่สำหรับ Android โค้ดนี้จะเซฟลงโฟลเดอร์ Download ตามที่คุณเขียนไว้เดิมครับ

Future<void> exportCSV(String fileName, String csvData) async {
  if (Platform.isAndroid) {
    if (!await Permission.manageExternalStorage.isGranted) {
      var status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        throw Exception("แอปจำเป็นต้องได้รับสิทธิ์ 'เข้าถึงไฟล์ทั้งหมด' (All files access)");
      }
    }
    
    final path = "/storage/emulated/0/Download/$fileName";
    final file = File(path);
    await file.writeAsString('\uFEFF$csvData');
  } else {
    throw Exception("โค้ดนี้ตั้งค่าไว้สำหรับ Android หากต้องการใช้ iOS ต้องเพิ่ม path_provider");
  }
}