import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // 1. เพิ่ม import นี้

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final MapController _mapController = MapController();
  LatLng _currentPosition = const LatLng(13.7563, 100.5018);
  bool _isLoading = true;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndGetLocation();
  }

  Future<void> _checkPermissionAndGetLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError("กรุณาอนุญาตสิทธิ์การเข้าถึงตำแหน่ง");
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
          _isLoading = false;
        });

        if (_mapReady) {
          _mapController.move(_currentPosition, 15.0);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError("ไม่สามารถดึงตำแหน่งได้: $e");
      }
    }
  }

  // 2. ฟังก์ชันบันทึกข้อมูลลง Firestore
  Future<void> _saveLocationToFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError("กรุณาเข้าสู่ระบบก่อนบันทึกข้อมูล");
      return;
    }

    try {
      // แสดง Loading ขณะบันทึก
      showDialog(
        context: context, 
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator())
      );

      // ส่งข้อมูลไปที่ Collection ชื่อ 'soil_data'
      await FirebaseFirestore.instance.collection('soil_data').add({
        'uid': user.uid, // เก็บว่าใครเป็นคนบันทึก
        'email': user.email,
        'latitude': _currentPosition.latitude,
        'longitude': _currentPosition.longitude,
        'timestamp': FieldValue.serverTimestamp(), // เวลาที่บันทึก
        // 'moisture': 0, // (เตรียมไว้) รอรับค่าความชื้นจาก ESP32
        // 'npk_value': 0, // (เตรียมไว้) รอรับค่า NPK
      });

      if (mounted) {
        Navigator.pop(context); // ปิด Loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("บันทึกพิกัดสำเร็จ!"),
            backgroundColor: Colors.green,
          )
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // ปิด Loading
        _showError("เกิดข้อผิดพลาด: $e");
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("บันทึกพิกัดตรวจดิน"),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          )
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: 15.0,
              minZoom: 3.0,
              maxZoom: 18.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate, 
              ),
              onMapReady: () => setState(() => _mapReady = true),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.soil_app',
                tileDisplay: const TileDisplay.fadeIn(duration: Duration(milliseconds: 300)),
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentPosition,
                    width: 45,
                    height: 45,
                    child: const Icon(Icons.location_on, color: Colors.red, size: 45),
                  ),
                ],
              ),
            ],
          ),
          
          // แถบแสดงพิกัด (ปรับให้เล็กลงหน่อย)
          Positioned(
            top: 15,
            left: 15,
            right: 15,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  "Lat: ${_currentPosition.latitude.toStringAsFixed(5)}, Lon: ${_currentPosition.longitude.toStringAsFixed(5)}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),

          // 3. ปุ่มบันทึกข้อมูล (อยู่ด้านล่าง)
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: ElevatedButton.icon(
              onPressed: _saveLocationToFirestore,
              icon: const Icon(Icons.save),
              label: const Text("บันทึกตำแหน่งนี้", style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ),

          if (_isLoading)
            Container(
              color: Colors.white.withOpacity(0.8),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
      // ปุ่มรีเฟรช GPS ย้ายไปมุมขวาล่างเหนือปุ่มบันทึก
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 60),
        child: FloatingActionButton(
          onPressed: _checkPermissionAndGetLocation,
          backgroundColor: Colors.white,
          child: const Icon(Icons.my_location, color: Colors.green),
        ),
      ),
    );
  }
}