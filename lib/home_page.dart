import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // แนะนำให้เพิ่ม package นี้เพื่อจัดรูปแบบเวลา (หรือใช้แบบธรรมดาก็ได้)

class HomePage extends StatefulWidget {
  final String gardenId;
  final String inspectionDateId;

  const HomePage({
    super.key,
    required this.gardenId,
    required this.inspectionDateId,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final MapController _mapController = MapController();
  LatLng _currentPosition = const LatLng(13.7563, 100.5018); // พิกัดสำหรับปุ่มบันทึก
  bool _isLoadingLocation = true;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  // ฟังก์ชันดึงพิกัดปัจจุบัน (เอาไว้สำหรับตอนกดปุ่ม + เพื่อบันทึกจุดใหม่)
  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
          _isLoadingLocation = false;
        });
        // เลื่อนแผนที่ไปหาตำแหน่งปัจจุบันแค่ครั้งแรกพอ
        _mapController.move(_currentPosition, 16.0);
      }
    } catch (e) {
      print("Error getting location: $e");
    }
  }

  // ฟังก์ชันบันทึกจุดใหม่ (New Point)
  Future<void> _addNewPoint() async {
    // อัปเดตพิกัดล่าสุดก่อนบันทึก
    await _getCurrentLocation(); 
    
    try {
      await FirebaseFirestore.instance
          .collection('gardens').doc(widget.gardenId)
          .collection('inspections').doc(widget.inspectionDateId)
          .collection('points').add({
            'latitude': _currentPosition.latitude,
            'longitude': _currentPosition.longitude,
            'timestamp': FieldValue.serverTimestamp(),
            'n_value': 0, // รอค่าจริง
            'p_value': 0,
            'k_value': 0,
            'moisture': 0,
          });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("เพิ่มจุดตรวจใหม่แล้ว!"), backgroundColor: Colors.green)
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // ฟังก์ชันแสดงรายละเอียดเมื่อกดที่หมุด
  void _showMarkerDetails(Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("ข้อมูลจุดตรวจ", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildValueBox("N", "${data['n_value']}", Colors.blue),
                  _buildValueBox("P", "${data['p_value']}", Colors.green),
                  _buildValueBox("K", "${data['k_value']}", Colors.orange),
                ],
              ),
              const SizedBox(height: 10),
              Text("ความชื้น: ${data['moisture']}%"),
            ],
          ),
        );
      },
    );
  }

  Widget _buildValueBox(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color),
          ),
          child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  // แปลง Timestamp เป็นเวลาที่อ่านง่าย
  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return "-";
    DateTime date = timestamp.toDate();
    return "${date.hour}:${date.minute.toString().padLeft(2, '0')} น.";
  }

  @override
  Widget build(BuildContext context) {
    // Stream หลักที่ดึงข้อมูลจุดตรวจทั้งหมดในวันนี้
    var pointsStream = FirebaseFirestore.instance
        .collection('gardens').doc(widget.gardenId)
        .collection('inspections').doc(widget.inspectionDateId)
        .collection('points')
        .orderBy('timestamp', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text("แผนที่และข้อมูลจุดตรวจ"),
        backgroundColor: Colors.green,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: pointsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          var docs = snapshot.data!.docs;

          // 1. เตรียม Marker สำหรับแผนที่
          List<Marker> mapMarkers = docs.map((doc) {
            var data = doc.data() as Map<String, dynamic>;
            double lat = data['latitude'] ?? 0.0;
            double long = data['longitude'] ?? 0.0;

            return Marker(
              point: LatLng(lat, long),
              width: 40,
              height: 40,
              child: GestureDetector(
                onTap: () => _showMarkerDetails(data), // กดแล้วโชว์ NPK
                child: const Icon(Icons.location_on, color: Colors.red, size: 40),
              ),
            );
          }).toList();

          // เพิ่ม Marker ตำแหน่งปัจจุบันเข้าไปด้วย (สีน้ำเงิน) จะได้รู้ว่าตัวเราอยู่ไหน
          mapMarkers.add(
            Marker(
              point: _currentPosition,
              width: 40,
              height: 40,
              child: const Icon(Icons.my_location, color: Colors.blue, size: 30), // ตัวเรา
            ),
          );

          return Column(
            children: [
              // --- ส่วนที่ 1: แผนที่ (ครึ่งบน) ---
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.45, // สูง 45% ของจอ
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentPosition, // เริ่มต้นที่ตัวเรา
                    initialZoom: 16.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.soil_app',
                    ),
                    MarkerLayer(markers: mapMarkers), // แสดงหมุดทั้งหมด
                  ],
                ),
              ),

              // --- ส่วนที่ 2: รายการข้อมูล (ครึ่งล่าง) ---
              Container(
                padding: const EdgeInsets.all(10),
                color: Colors.green[50],
                width: double.infinity,
                child: Text(
                  "รายการตรวจ (${docs.length} จุด)", 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.green,
                          child: Text("${index + 1}", style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text("เวลา: ${_formatTime(data['timestamp'])}"),
                        subtitle: Row(
                          children: [
                            Text("N: ${data['n_value']} ", style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold)),
                            Text("P: ${data['p_value']} ", style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.bold)),
                            Text("K: ${data['k_value']}", style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.bold)),
                          ],
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          // กดที่ลิสต์แล้วเลื่อนแผนที่ไปหาจุดนั้น
                          _mapController.move(
                            LatLng(data['latitude'], data['longitude']), 
                            18.0
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      
      // ปุ่มบวก ลอยอยู่มุมขวาล่างเหมือนเดิม
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNewPoint,
        label: const Text("บันทึกจุดนี้"),
        icon: const Icon(Icons.add_location_alt),
        backgroundColor: Colors.green,
      ),
    );
  }
}