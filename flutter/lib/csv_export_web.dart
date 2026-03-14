import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

Future<void> exportCSV(String fileName, String csvData) async {
  try {
    // 1. เข้ารหัสไฟล์และใส่ BOM เพื่อให้ Excel อ่านภาษาไทยได้
    final bytes = Uint8List.fromList(utf8.encode('\uFEFF$csvData'));
    
    // 2. แปลงข้อมูลเป็นไฟล์เสมือน (XFile)
    final xFile = XFile.fromData(
      bytes,
      name: fileName,
      mimeType: 'text/csv',
    );
    
    // 3. เรียกหน้าต่างแชร์ของระบบ (Share Sheet)
    await Share.shareXFiles([xFile], text: 'ข้อมูลรอบตรวจ: $fileName');
    
  } catch (e) {
    debugPrint("Export Error: $e");
  }
}