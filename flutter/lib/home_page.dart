import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_service.dart';
import 'bluetooth_scan_dialog.dart';

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

  bool _isBlueConnected = false;
  bool _isAutoSaving = false;
  bool _isToggling = false;

  // ✅ เพิ่ม: สำหรับ listen event จาก background service
  StreamSubscription? _ackSubscription;

  @override
  void initState() {
    super.initState();
    _checkAndEnableBluetooth();
    _getCurrentLocation();
    _checkBluetoothStatus();
    _checkAutoSaveStatus();

    // ✅ เพิ่ม: รับ event 'sendAckToBLE' จาก background isolate
    // Background ไม่สามารถ write BLE ได้เพราะ connectedDevice อยู่ใน UI isolate
    // ให้ UI isolate เป็นคน writeAck() แทน
    _ackSubscription = FlutterBackgroundService()
        .on('sendAckToBLE')
        .listen((event) async {
      debugPrint('[UI] รับ sendAckToBLE event จาก background');
      if (BLEService().isConnected) {
        await BLEService().writeAck();
        debugPrint('[UI] writeAck() สำเร็จ → ESP32 จะแสดง "บันทึกสำเร็จ!" บน LCD');
      } else {
        debugPrint('[UI] BLE ไม่ได้เชื่อมต่อ — ไม่สามารถส่ง ACK ได้');
      }
    });
  }

  @override
  void dispose() {
    // ✅ cancel subscription เมื่อ widget ถูกทำลาย
    _ackSubscription?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // Bluetooth
  // ─────────────────────────────────────────────
  Future<void> _checkAndEnableBluetooth() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (await FlutterBluePlus.isSupported == false) {
      debugPrint("อุปกรณ์นี้ไม่รองรับ Bluetooth");
      return;
    }

    BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.off) {
      if (Platform.isAndroid) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (e) {
          if (mounted) _showBluetoothWarningDialog();
        }
      } else {
        if (mounted) _showBluetoothWarningDialog();
      }
    }
  }

  void _showBluetoothWarningDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.bluetooth_disabled, color: Colors.red),
            SizedBox(width: 10),
            Text("บลูทูธปิดอยู่"),
          ],
        ),
        content: const Text(
            "กรุณาเปิดบลูทูธในตั้งค่าโทรศัพท์ของคุณ เพื่อเชื่อมต่อกับเซนเซอร์ NPK"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("ตกลง"),
          )
        ],
      ),
    );
  }

  void _checkBluetoothStatus() {
    setState(() {
      _isBlueConnected = BLEService().isConnected;
    });
  }

  void _confirmDisconnect() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ตัดการเชื่อมต่อ"),
        content: const Text("คุณต้องการเลิกเชื่อมต่อกับอุปกรณ์ใช่หรือไม่?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("ยกเลิก")),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) =>
                    const Center(child: CircularProgressIndicator()),
              );
              try {
                await BLEService().disconnect();
                if (mounted) {
                  setState(() => _isBlueConnected = false);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("ตัดการเชื่อมต่อแล้ว")),
                  );
                }
              } catch (e) {
                if (mounted) Navigator.pop(context);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("ตัดการเชื่อมต่อ"),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Auto Save
  // ─────────────────────────────────────────────
  Future<void> _checkAutoSaveStatus() async {
    final service = FlutterBackgroundService();
    bool isRunning = await service.isRunning();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? activeInspectId = prefs.getString('bg_inspect_id');

    if (mounted) {
      setState(() {
        _isAutoSaving =
            isRunning && (activeInspectId == widget.inspectionDateId);
      });
    }
  }

  Future<void> _toggleAutoSave() async {
    if (await Permission.notification.isDenied) {
      final status = await Permission.notification.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    "กรุณาอนุญาตการแจ้งเตือน เพื่อใช้งานระบบบันทึกเบื้องหลัง")),
          );
        }
        return;
      }
    }

    if (_isToggling) return;
    setState(() => _isToggling = true);

    final service = FlutterBackgroundService();

    try {
      if (_isAutoSaving) {
        service.invoke("stopService");
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          setState(() => _isAutoSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("หยุดการบันทึกอัตโนมัติแล้ว")),
          );
        }
      } else {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('bg_garden_id', widget.gardenId);
        await prefs.setString('bg_inspect_id', widget.inspectionDateId);

        bool isRunning = await service.isRunning();
        if (isRunning) {
          service.invoke("stopService");
          await Future.delayed(const Duration(milliseconds: 800));
        }

        await service.startService();

        await Future.delayed(const Duration(milliseconds: 500));
        service.invoke('updateIds', {
          'garden_id': widget.gardenId,
          'inspect_id': widget.inspectionDateId,
        });

        if (mounted) {
          setState(() => _isAutoSaving = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    "เปิดโหมดบันทึกอัตโนมัติแล้ว! (ทำงานตอนปิดจอได้)"),
                backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      debugPrint("Toggle Service Error: $e");
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }

  // ─────────────────────────────────────────────
  // Location
  // ─────────────────────────────────────────────
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

  // ─────────────────────────────────────────────
  // Points
  // ─────────────────────────────────────────────
  void _showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
  }

  Future<void> _addNewPoint() async {
    _showLoadingDialog(context);

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
        });
        _mapController.move(_currentPosition, 18.0);
      }

      int n = 0, p = 0, k = 0, moisture = 0;
      String source = "Manual";

      if (_isBlueConnected && BLEService().isConnected) {
        try {
          var data = await BLEService().readNPK();
          if (data.isNotEmpty) {
            n = data['n'] ?? 0;
            p = data['p'] ?? 0;
            k = data['k'] ?? 0;
            moisture = data['moisture'] ?? 0;
            source = "Sensor (BLE)";
          }
        } catch (e) {
          debugPrint("Read error: $e");
        }
      }

      if (n == 0 && p == 0 && k == 0) {
        if (mounted) Navigator.pop(context);

        if (mounted) {
          bool? confirm = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  SizedBox(width: 10),
                  Text("แจ้งเตือนค่าเป็น 0"),
                ],
              ),
              content: const Text(
                "ค่า N P K เป็น 0 ทั้งหมด\n\n"
                "• หากคุณต้องการค่าจริง: กรุณาเชื่อมต่อ ESP32 หรือตรวจสอบเซนเซอร์\n"
                "• หากต้องการบันทึกค่า 0: กดยืนยันด้านล่าง",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("ยกเลิก (ไปเชื่อมต่อ)"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                  child: const Text("บันทึกค่า 0",
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );

          if (confirm != true) return;
          if (mounted) _showLoadingDialog(context);
        }
      }

      await FirebaseFirestore.instance
          .collection('gardens')
          .doc(widget.gardenId)
          .collection('inspections')
          .doc(widget.inspectionDateId)
          .collection('points')
          .add({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'n_value': n,
        'p_value': p,
        'k_value': k,
        'moisture': moisture,
        'source': source,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("บันทึกสำเร็จ! (N:$n P:$p K:$k)"),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("เกิดข้อผิดพลาด: $e"),
              backgroundColor: Colors.red),
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
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("ยกเลิก")),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('gardens')
                  .doc(widget.gardenId)
                  .collection('inspections')
                  .doc(widget.inspectionDateId)
                  .collection('points')
                  .doc(docId)
                  .delete();

              setState(() => _selectedIndex = null);
              if (mounted) Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("ลบเรียบร้อย"),
                  backgroundColor: Colors.redAccent));
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("ลบ"),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // UI Helpers
  // ─────────────────────────────────────────────
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
                      const Text("ข้อมูลจุดตรวจ",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(_formatDateTime(data['timestamp']),
                          style: const TextStyle(
                              fontSize: 14, color: Colors.grey)),
                      if (data['source'] != null)
                        Text("ที่มา: ${data['source']}",
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                  if (isOwner)
                    IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          Navigator.pop(context);
                          _deletePoint(docId);
                        }),
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
              Center(
                  child: Text("ความชื้น: ${data['moisture']}%",
                      style: const TextStyle(fontSize: 16))),
            ],
          ),
        );
      },
    );
  }

  Widget _buildValueBox(String label, String value, Color color) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 18)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color)),
          child: Text(value,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  void _selectPoint(int index, LatLng location) {
    setState(() => _selectedIndex = index);
    _mapController.move(location, 18.0);
  }

  // ─────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    bool isOwner = (widget.userRole == 'owner');

    return Scaffold(
      appBar: AppBar(
        title: const Text("แผนที่และจุดตรวจ"),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: Icon(
              _isAutoSaving ? Icons.cloud_sync : Icons.cloud_off,
              color: _isAutoSaving ? Colors.yellowAccent : Colors.white,
            ),
            tooltip: _isAutoSaving
                ? "ปิดบันทึกอัตโนมัติ"
                : "เปิดบันทึกเบื้องหลัง",
            onPressed: _toggleAutoSave,
          ),
          IconButton(
            icon: Icon(
              _isBlueConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_searching,
              color: _isBlueConnected ? Colors.blue[100] : Colors.white,
            ),
            tooltip: _isBlueConnected ? "ตัดการเชื่อมต่อ" : "ค้นหาอุปกรณ์",
            onPressed: () async {
              if (_isBlueConnected) {
                _confirmDisconnect();
              } else {
                BluetoothAdapterState state =
                    await FlutterBluePlus.adapterState.first;
                if (state == BluetoothAdapterState.off) {
                  _checkAndEnableBluetooth();
                } else {
                  await showBluetoothScanDialog(
                    context: context,
                    onConnected: () =>
                        setState(() => _isBlueConnected = true),
                    onDisconnected: () =>
                        setState(() => _isBlueConnected = false),
                  );
                }
              }
            },
          ),
          PopupMenuButton<bool>(
            icon: const Icon(Icons.sort),
            onSelected: (bool value) => setState(() {
              _isDescending = value;
              _selectedIndex = null;
            }),
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: true, child: Text('เรียง: ล่าสุด -> เก่าสุด')),
              const PopupMenuItem(
                  value: false, child: Text('เรียง: เก่าสุด -> ล่าสุด')),
            ],
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('gardens')
            .doc(widget.gardenId)
            .collection('inspections')
            .doc(widget.inspectionDateId)
            .collection('points')
            .orderBy('timestamp', descending: _isDescending)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(child: Text("Error: ${snapshot.error}"));
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          var docs = snapshot.data!.docs;
          List<Marker> mapMarkers = [];

          for (int i = 0; i < docs.length; i++) {
            var data = docs[i].data() as Map<String, dynamic>;
            LatLng point =
                LatLng(data['latitude'] ?? 0, data['longitude'] ?? 0);
            bool isSelected = (i == _selectedIndex);

            mapMarkers.add(Marker(
              point: point,
              width: 60,
              height: 60,
              child: GestureDetector(
                onTap: () {
                  _selectPoint(i, point);
                  _showMarkerDetails(docs[i].id, data);
                },
                child: isSelected
                    ? const BouncingPin()
                    : const Icon(Icons.location_on,
                        color: Colors.red, size: 40),
              ),
            ));
          }

          if (!_isLoadingLocation) {
            mapMarkers.add(Marker(
                point: _currentPosition,
                width: 40,
                height: 40,
                child: const Icon(Icons.my_location,
                    color: Colors.blue, size: 30)));
          }

          return Column(
            children: [
              if (_isAutoSaving)
                Container(
                  color: Colors.yellow[700],
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.sync, size: 16),
                      SizedBox(width: 8),
                      Text("กำลังบันทึกพิกัดอัตโนมัติเบื้องหลัง...",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.40,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                      initialCenter: _currentPosition,
                      initialZoom: 16.0,
                      onTap: (_, __) =>
                          setState(() => _selectedIndex = null)),
                  children: [
                    TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.soil_app'),
                    MarkerLayer(markers: mapMarkers),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                color: Colors.green[50],
                width: double.infinity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("รายการตรวจ (${docs.length} จุด)",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                        _isDescending
                            ? "(ล่าสุดก่อน)"
                            : "(เก่าสุดก่อน)",
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    bool isSelected = (index == _selectedIndex);
                    return Card(
                      color:
                          isSelected ? Colors.green[100] : Colors.white,
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      child: ListTile(
                        leading: CircleAvatar(
                            backgroundColor:
                                isSelected ? Colors.blue : Colors.green,
                            child: Text("${index + 1}",
                                style: const TextStyle(
                                    color: Colors.white))),
                        title: Text(
                            "บันทึกเมื่อ: ${_formatDateTime(data['timestamp'])}",
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            "N: ${data['n_value']} P: ${data['p_value']} K: ${data['k_value']}"),
                        trailing: isOwner
                            ? IconButton(
                                icon: const Icon(Icons.delete,
                                    color: Colors.red),
                                onPressed: () =>
                                    _deletePoint(docs[index].id))
                            : null,
                        onTap: () => _selectPoint(index,
                            LatLng(data['latitude'], data['longitude'])),
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
        label: Text(_isBlueConnected ? "อ่านค่า & บันทึก" : "บันทึก"),
        icon: Icon(_isBlueConnected
            ? Icons.bluetooth_audio
            : Icons.add_location_alt),
        backgroundColor:
            _isBlueConnected ? Colors.blue[700] : Colors.green,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Bouncing Pin Animation
// ─────────────────────────────────────────────
class BouncingPin extends StatefulWidget {
  const BouncingPin({super.key});
  @override
  State<BouncingPin> createState() => _BouncingPinState();
}

class _BouncingPinState extends State<BouncingPin>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        duration: const Duration(milliseconds: 1000), vsync: this)
      ..repeat(reverse: true);
    _animation = Tween<double>(begin: 0, end: -15).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
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
        builder: (context, child) => Transform.translate(
            offset: Offset(0, _animation.value), child: child),
        child: const Icon(Icons.location_on, color: Colors.blue, size: 50));
  }
}