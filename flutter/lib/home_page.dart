import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb; 
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

class HomePage extends StatefulWidget {
  final String gardenId;
  final String inspectionDateId;
  final String userRole;

  const HomePage({
    super.key,
    required this.gardenId,
    required this.inspectionDateId,
    required this.userRole,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final MapController _mapController = MapController();
  LatLng _currentPosition = const LatLng(13.7563, 100.5018);
  bool _isLoadingLocation = true;
  int? _selectedIndex;
  bool _isDescending = true;

  // สำหรับการทำงานบน Web
  StreamSubscription<DocumentSnapshot>? _webSubscription;
  int? _lastN, _lastP, _lastK;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();

    // เช็กแพลตฟอร์มเพื่อเลือกระบบดักฟังที่เหมาะสม
    if (kIsWeb) {
      _startWebForegroundListening();
    } else {
      _startBackgroundListening();
    }
  }

  @override
  void dispose() {
    // ปิดการดักฟังเมื่อออกหน้านี้
    if (kIsWeb) {
      _webSubscription?.cancel();
    } else {
      FlutterBackgroundService().invoke('stopService');
    }
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
          _isLoadingLocation = false;
        });
        _mapController.move(_currentPosition, 16.0);
      }
    } catch (e) {
      debugPrint("Error getting location: $e");
    }
  }

  // --- ฟังก์ชันสำหรับ Web (ต้องเปิดหน้าจอค้าง) ---
  void _startWebForegroundListening() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("ระบบบันทึกทำงานแล้ว (ห้ามปิด/พับหน้าเว็บ)"), backgroundColor: Colors.orange)
    );

    bool isFirstLoad = true; // [สำคัญ] ป้องกันการบันทึกค่าแรกสุดตอนโหลดหน้าเว็บ

    _webSubscription = FirebaseFirestore.instance
        .collection('ESP01')
        .doc('NPK')
        .snapshots()
        .listen((snapshot) async {
      
      if (snapshot.exists && snapshot.data() != null) {
        var data = snapshot.data() as Map<String, dynamic>;
        int n = data['N'] ?? 0;
        int p = data['P'] ?? 0;
        int k = data['K'] ?? 0;

        // 1. ถ้าเป็นการโหลดครั้งแรก ให้จำค่าไว้ แต่ห้ามบันทึก
        if (isFirstLoad) {
          isFirstLoad = false;
          _lastN = n; _lastP = p; _lastK = k;
          return;
        }

        // 2. ถ้าค่าไม่มีการเปลี่ยนแปลง ให้ข้ามไป
        if (n == _lastN && p == _lastP && k == _lastK) return;
        
        _lastN = n; _lastP = p; _lastK = k;

        try {
          Position position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high);
          DateTime currentTime = DateTime.now(); // เวลา ณ วินาทีที่ ESP32 ยิงค่ามาเปลี่ยน

          await FirebaseFirestore.instance
              .collection('gardens').doc(widget.gardenId)
              .collection('inspections').doc(widget.inspectionDateId)
              .collection('points').add({
            'latitude': position.latitude,
            'longitude': position.longitude,
            'timestamp': Timestamp.fromDate(currentTime), 
            'n_value': n, 'p_value': p, 'k_value': k,
            'moisture': 0, 
            'source': "ESP32 (Web-Auto)",
          });
          
          if (mounted) {
            String timeStr = DateFormat('HH:mm:ss').format(currentTime);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("บันทึกจาก Web สำเร็จ! (เวลา: $timeStr)"), backgroundColor: Colors.green)
            );
          }
        } catch (e) {
          debugPrint("Web Save Error: $e");
        }
      }
    });
  }

  // --- ฟังก์ชันสำหรับมือถือ (พับจอได้) ---
  Future<void> _startBackgroundListening() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('bg_gardenId', widget.gardenId);
    await prefs.setString('bg_inspectionId', widget.inspectionDateId);

    final service = FlutterBackgroundService();
    bool isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("ระบบบันทึกอัตโนมัติทำงานแล้ว (พับจอมือถือได้)"),
            backgroundColor: Colors.green,
          )
        );
      }
    }
  }

  void _deletePoint(String docId) {
     showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ยืนยันการลบ"),
        content: const Text("ต้องการลบจุดตรวจนี้ใช่ไหม?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ยกเลิก")),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('gardens').doc(widget.gardenId)
                  .collection('inspections').doc(widget.inspectionDateId)
                  .collection('points').doc(docId).delete();
              
              setState(() => _selectedIndex = null);
              if (mounted) Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ลบเรียบร้อย"), backgroundColor: Colors.redAccent));
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("ลบ"),
          ),
        ],
      ),
    );
  }
  
  String _formatDateTime(Timestamp? timestamp) {
    if (timestamp == null) return "-";
    return DateFormat('dd/MM/yyyy HH:mm').format(timestamp.toDate());
  }

  void _showMarkerDetails(String docId, Map<String, dynamic> data) {
    bool isOwner = (widget.userRole == 'owner');
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("ข้อมูลจุดตรวจ", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(_formatDateTime(data['timestamp']), style: const TextStyle(fontSize: 14, color: Colors.grey)),
                      if (data['source'] != null) Text("ที่มา: ${data['source']}", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                  if (isOwner)
                    IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () { Navigator.pop(context); _deletePoint(docId); }),
                ],
              ),
              const Divider(),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildValueBox("N", "${data['n_value']}", Colors.blue),
                  _buildValueBox("P", "${data['p_value']}", Colors.green),
                  _buildValueBox("K", "${data['k_value']}", Colors.orange),
                ],
              ),
              const SizedBox(height: 20),
              Center(child: Text("ความชื้น: ${data['moisture'] ?? 0}%", style: const TextStyle(fontSize: 16))),
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color)),
          child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  void _selectPoint(int index, LatLng location) {
    setState(() => _selectedIndex = index);
    _mapController.move(location, 18.0);
  }

  @override
  Widget build(BuildContext context) {
    bool isOwner = (widget.userRole == 'owner');

    return Scaffold(
      appBar: AppBar(
        title: const Text("แผนที่และจุดตรวจ"),
        backgroundColor: Colors.green,
        actions: [
          PopupMenuButton<bool>(
            icon: const Icon(Icons.sort),
            onSelected: (bool value) => setState(() { _isDescending = value; _selectedIndex = null; }),
            itemBuilder: (context) => [
              const PopupMenuItem(value: true, child: Text('เรียง: ล่าสุด -> เก่าสุด')),
              const PopupMenuItem(value: false, child: Text('เรียง: เก่าสุด -> ล่าสุด')),
            ],
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('gardens').doc(widget.gardenId)
            .collection('inspections').doc(widget.inspectionDateId)
            .collection('points')
            .orderBy('timestamp', descending: _isDescending) 
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          var docs = snapshot.data!.docs;
          List<Marker> mapMarkers = [];
          
          for (int i = 0; i < docs.length; i++) {
            var data = docs[i].data() as Map<String, dynamic>;
            LatLng point = LatLng(data['latitude'] ?? 0, data['longitude'] ?? 0);
            bool isSelected = (i == _selectedIndex);

            mapMarkers.add(Marker(
              point: point, width: 60, height: 60,
              child: GestureDetector(
                onTap: () { _selectPoint(i, point); _showMarkerDetails(docs[i].id, data); },
                child: isSelected ? const BouncingPin() : const Icon(Icons.location_on, color: Colors.red, size: 40),
              ),
            ));
          }

          if (!_isLoadingLocation) {
            mapMarkers.add(Marker(point: _currentPosition, width: 40, height: 40, child: const Icon(Icons.my_location, color: Colors.blue, size: 30)));
          }

          return Column(
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.45,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(initialCenter: _currentPosition, initialZoom: 16.0, onTap: (_, __) => setState(() => _selectedIndex = null)),
                  children: [
                    TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.soil_app'),
                    MarkerLayer(markers: mapMarkers),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                color: Colors.green[50],
                width: double.infinity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("รายการตรวจ (${docs.length} จุด)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(_isDescending ? "(ล่าสุดก่อน)" : "(เก่าสุดก่อน)", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    bool isSelected = (index == _selectedIndex);
                    return Card(
                      color: isSelected ? Colors.green[100] : Colors.white,
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: isSelected ? Colors.blue : Colors.green, child: Text("${index + 1}", style: const TextStyle(color: Colors.white))),
                        title: Text("บันทึกเมื่อ: ${_formatDateTime(data['timestamp'])}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        subtitle: Text("N: ${data['n_value']} P: ${data['p_value']} K: ${data['k_value']}"),
                        trailing: isOwner ? IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deletePoint(docs[index].id)) : null,
                        onTap: () => _selectPoint(index, LatLng(data['latitude'], data['longitude'])),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class BouncingPin extends StatefulWidget {
  const BouncingPin({super.key});
  @override
  State<BouncingPin> createState() => _BouncingPinState();
}

class _BouncingPinState extends State<BouncingPin> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this)..repeat(reverse: true);
    _animation = Tween<double>(begin: 0, end: -15).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _animation, builder: (context, child) => Transform.translate(offset: Offset(0, _animation.value), child: child), child: const Icon(Icons.location_on, color: Colors.blue, size: 50));
  }
}