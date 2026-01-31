import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomePage extends StatefulWidget {
  final String gardenId;
  final String inspectionDateId;
  final String userRole; // รับ Role มาเพื่อเช็คสิทธิ์

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
  
  // จำว่าเลือกหมุดไหนอยู่
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

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
        _mapController.move(_currentPosition, 16.0);
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  Future<void> _addNewPoint() async {
    await _getCurrentLocation(); 
    try {
      await FirebaseFirestore.instance
          .collection('gardens').doc(widget.gardenId)
          .collection('inspections').doc(widget.inspectionDateId)
          .collection('points').add({
            'latitude': _currentPosition.latitude,
            'longitude': _currentPosition.longitude,
            'timestamp': FieldValue.serverTimestamp(),
            'n_value': 0, 'p_value': 0, 'k_value': 0, 'moisture': 0,
          });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("เพิ่มจุดตรวจใหม่แล้ว!"), backgroundColor: Colors.green)
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // ฟังก์ชันลบ (ใช้ได้เฉพาะ Owner)
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
              
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("ลบเรียบร้อย"), backgroundColor: Colors.redAccent)
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("ลบ"),
          ),
        ],
      ),
    );
  }

  void _showMarkerDetails(String docId, Map<String, dynamic> data) {
    // เช็คสิทธิ์ก่อนแสดงปุ่มลบใน Modal
    bool isOwner = (widget.userRole == 'owner');

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 250,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("ข้อมูลจุดตรวจ", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  // ปุ่มลบ: แสดงเฉพาะ Owner
                  if (isOwner)
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        Navigator.pop(context);
                        _deletePoint(docId);
                      },
                    )
                ],
              ),
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

  void _selectPoint(int index, LatLng location) {
    setState(() => _selectedIndex = index);
    _mapController.move(location, 18.0);
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return "-";
    DateTime date = timestamp.toDate();
    return "${date.hour}:${date.minute.toString().padLeft(2, '0')} น.";
  }

  @override
  Widget build(BuildContext context) {
    // เช็คสิทธิ์เพื่อใช้แสดงปุ่มลบใน List
    bool isOwner = (widget.userRole == 'owner');

    return Scaffold(
      appBar: AppBar(
        title: const Text("แผนที่และข้อมูลจุดตรวจ"),
        backgroundColor: Colors.green,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('gardens').doc(widget.gardenId)
            .collection('inspections').doc(widget.inspectionDateId)
            .collection('points')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          var docs = snapshot.data!.docs;

          List<Marker> mapMarkers = [];
          for (int i = 0; i < docs.length; i++) {
            var data = docs[i].data() as Map<String, dynamic>;
            String docId = docs[i].id;
            LatLng point = LatLng(data['latitude'] ?? 0, data['longitude'] ?? 0);
            
            bool isSelected = (i == _selectedIndex);

            mapMarkers.add(
              Marker(
                point: point,
                width: 60,
                height: 60,
                child: GestureDetector(
                  onTap: () {
                    _selectPoint(i, point);
                    _showMarkerDetails(docId, data);
                  },
                  child: isSelected 
                      ? const BouncingPin() 
                      : const Icon(Icons.location_on, color: Colors.red, size: 40),
                ),
              ),
            );
          }

          mapMarkers.add(
            Marker(
              point: _currentPosition,
              width: 40,
              height: 40,
              child: const Icon(Icons.my_location, color: Colors.blue, size: 30),
            ),
          );

          return Column(
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.45,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentPosition,
                    initialZoom: 16.0,
                    onTap: (_, __) => setState(() => _selectedIndex = null),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.soil_app',
                    ),
                    MarkerLayer(markers: mapMarkers),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                color: Colors.green[50],
                width: double.infinity,
                child: Text("รายการตรวจ (${docs.length} จุด)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100), // ดันก้นหนีปุ่มบวก
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    String docId = docs[index].id;
                    bool isSelected = (index == _selectedIndex);
                    
                    return Card(
                      color: isSelected ? Colors.green[100] : Colors.white,
                      shape: isSelected 
                          ? RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: const BorderSide(color: Colors.blue, width: 2))
                          : null,
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSelected ? Colors.blue : Colors.green,
                          child: Text("${index + 1}", style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text("เวลา: ${_formatTime(data['timestamp'])}"),
                        subtitle: Text("N: ${data['n_value']} P: ${data['p_value']} K: ${data['k_value']}"),
                        
                        // ปุ่มลบใน List: แสดงเฉพาะ Owner
                        trailing: isOwner ? IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deletePoint(docId),
                        ) : null, // Worker จะไม่เห็นปุ่มนี้

                        onTap: () {
                          _selectPoint(index, LatLng(data['latitude'], data['longitude']));
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNewPoint,
        label: const Text("บันทึกจุดนี้"),
        icon: const Icon(Icons.add_location_alt),
        backgroundColor: Colors.green,
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
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0, end: -15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _animation.value),
          child: child,
        );
      },
      child: const Icon(Icons.location_on, color: Colors.blue, size: 50),
    );
  }
}