import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class SoilAnalysisPage extends StatefulWidget {
  final String gardenId;
  final String inspectionDateId;

  const SoilAnalysisPage({
    super.key,
    required this.gardenId,
    required this.inspectionDateId,
  });

  @override
  State<SoilAnalysisPage> createState() => _SoilAnalysisPageState();
}

class _SoilAnalysisPageState extends State<SoilAnalysisPage> {
  final MapController _mapController = MapController();

  // ค่า NPK ที่คาดหวัง
  final TextEditingController _expectedNController =
      TextEditingController(text: '30');
  final TextEditingController _expectedPController =
      TextEditingController(text: '30');
  final TextEditingController _expectedKController =
      TextEditingController(text: '30');

  // tolerance ± %
  double _tolerance = 40.0;

  List<_PointData> _points = [];
  bool _isLoading = false;
  bool _hasAnalyzed = false;

  int get _expectedN => int.tryParse(_expectedNController.text) ?? 0;
  int get _expectedP => int.tryParse(_expectedPController.text) ?? 0;
  int get _expectedK => int.tryParse(_expectedKController.text) ?? 0;

  @override
  void dispose() {
    _expectedNController.dispose();
    _expectedPController.dispose();
    _expectedKController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // วิเคราะห์ค่าแต่ละจุด
  // ─────────────────────────────────────────────
  _PointStatus _evaluatePoint(_PointData p) {
    if (_expectedN == 0 && _expectedP == 0 && _expectedK == 0) {
      return _PointStatus.neutral;
    }

    double scoreN = _expectedN > 0 ? p.n / _expectedN : 1.0;
    double scoreP = _expectedP > 0 ? p.p / _expectedP : 1.0;
    double scoreK = _expectedK > 0 ? p.k / _expectedK : 1.0;

    double tLow = 1.0 - (_tolerance / 100);
    double tHigh = 1.0 + (_tolerance / 100);

    bool nOk = _expectedN == 0 || (scoreN >= tLow && scoreN <= tHigh);
    bool pOk = _expectedP == 0 || (scoreP >= tLow && scoreP <= tHigh);
    bool kOk = _expectedK == 0 || (scoreK >= tLow && scoreK <= tHigh);

    int okCount = [nOk, pOk, kOk].where((b) => b).length;

    if (okCount == 3) return _PointStatus.good;
    if (okCount == 2) return _PointStatus.warning;
    return _PointStatus.bad;
  }

  Future<void> _runAnalysis() async {
    setState(() => _isLoading = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('gardens')
          .doc(widget.gardenId)
          .collection('inspections')
          .doc(widget.inspectionDateId)
          .collection('points')
          .orderBy('timestamp', descending: false)
          .get();

      List<_PointData> pts = [];
      for (var doc in snapshot.docs) {
        final d = doc.data();
        pts.add(_PointData(
          id: doc.id,
          lat: (d['latitude'] as num?)?.toDouble() ?? 0,
          lng: (d['longitude'] as num?)?.toDouble() ?? 0,
          n: (d['n_value'] as num?)?.toInt() ?? 0,
          p: (d['p_value'] as num?)?.toInt() ?? 0,
          k: (d['k_value'] as num?)?.toInt() ?? 0,
          moisture: (d['moisture'] as num?)?.toInt() ?? 0,
          timestamp: d['timestamp'] as Timestamp?,
          source: d['source'] as String? ?? '-',
        ));
      }

      setState(() {
        _points = pts;
        _isLoading = false;
        _hasAnalyzed = true;
      });

      if (pts.isNotEmpty) {
        _mapController.move(
          LatLng(pts.first.lat, pts.first.lng),
          16.0,
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("เกิดข้อผิดพลาด: $e"),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─────────────────────────────────────────────
  // สรุปผล
  // ─────────────────────────────────────────────
  Map<_PointStatus, int> get _summary {
    Map<_PointStatus, int> map = {
      _PointStatus.good: 0,
      _PointStatus.warning: 0,
      _PointStatus.bad: 0,
      _PointStatus.neutral: 0,
    };
    for (var p in _points) {
      map[_evaluatePoint(p)] = (map[_evaluatePoint(p)] ?? 0) + 1;
    }
    return map;
  }

  // ─────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────
  Color _statusColor(_PointStatus s) {
    switch (s) {
      case _PointStatus.good:
        return Colors.green;
      case _PointStatus.warning:
        return Colors.orange;
      case _PointStatus.bad:
        return Colors.red;
      case _PointStatus.neutral:
        return Colors.grey;
    }
  }

  String _statusLabel(_PointStatus s) {
    switch (s) {
      case _PointStatus.good:
        return "ดี";
      case _PointStatus.warning:
        return "ปานกลาง";
      case _PointStatus.bad:
        return "ต้องปรับปรุง";
      case _PointStatus.neutral:
        return "ไม่ระบุ";
    }
  }

  IconData _statusIcon(_PointStatus s) {
    switch (s) {
      case _PointStatus.good:
        return Icons.check_circle;
      case _PointStatus.warning:
        return Icons.warning_amber_rounded;
      case _PointStatus.bad:
        return Icons.cancel;
      case _PointStatus.neutral:
        return Icons.help_outline;
    }
  }

  String _formatDateTime(Timestamp? ts) {
    if (ts == null) return "-";
    return DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate());
  }

  // ─────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("วิเคราะห์ค่าดิน NPK"),
        backgroundColor: Colors.teal,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ─── ส่วนกรอกค่าที่คาดหวัง ───
          _buildExpectedInput(),

          // ─── แผนที่ ───
          if (_hasAnalyzed) ...[
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.32,
              child: _buildMap(),
            ),
            // ─── สรุปผล ───
            _buildSummaryBar(summary),
          ],

          // ─── รายการจุด ───
          if (_hasAnalyzed && _points.isNotEmpty)
            Expanded(child: _buildPointList()),

          if (_hasAnalyzed && _points.isEmpty)
            const Expanded(
              child: Center(
                child: Text("ไม่มีข้อมูลจุดตรวจในรอบนี้",
                    style: TextStyle(fontSize: 16, color: Colors.grey)),
              ),
            ),
        ],
      ),
    );
  }

  // ─── กรอกค่าที่คาดหวัง ───
  Widget _buildExpectedInput() {
    return Container(
      color: Colors.teal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("ค่า NPK ที่คาดหวัง (mg/kg)",
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildNPKField("N (ไนโตรเจน)", _expectedNController, Colors.blue[200]!),
              const SizedBox(width: 8),
              _buildNPKField("P (ฟอสฟอรัส)", _expectedPController, Colors.green[200]!),
              const SizedBox(width: 8),
              _buildNPKField("K (โพแทสเซียม)", _expectedKController, Colors.orange[200]!),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text("ช่วงยอมรับ ±",
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.white,
                    thumbColor: Colors.white,
                    inactiveTrackColor: Colors.teal[300],
                    overlayColor: Colors.white24,
                  ),
                  child: Slider(
                    value: _tolerance,
                    min: 5,
                    max: 80,
                    divisions: 15,
                    onChanged: (v) => setState(() => _tolerance = v),
                  ),
                ),
              ),
              Text("${_tolerance.toInt()}%",
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _runAnalysis,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.teal))
                  : const Icon(Icons.analytics),
              label: Text(_isLoading ? "กำลังวิเคราะห์..." : "วิเคราะห์ผลดิน"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.teal[800],
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNPKField(
      String label, TextEditingController ctrl, Color fillColor) {
    return Expanded(
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontWeight: FontWeight.bold, fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 11),
          filled: true,
          fillColor: fillColor,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        ),
      ),
    );
  }

  // ─── แผนที่ ───
  Widget _buildMap() {
    List<Marker> markers = [];

    for (int i = 0; i < _points.length; i++) {
      final p = _points[i];
      final status = _evaluatePoint(p);
      final color = _statusColor(status);

      markers.add(Marker(
        point: LatLng(p.lat, p.lng),
        width: 56,
        height: 56,
        child: GestureDetector(
          onTap: () => _showPointDetail(p, status),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.25),
                  border: Border.all(color: color, width: 3),
                ),
              ),
              Text(
                "${i + 1}",
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ],
          ),
        ),
      ));
    }

    LatLng center = _points.isNotEmpty
        ? LatLng(_points.first.lat, _points.first.lng)
        : const LatLng(13.7563, 100.5018);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 16.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.soil_app',
        ),
        MarkerLayer(markers: markers),
      ],
    );
  }

  // ─── แถบสรุป ───
  Widget _buildSummaryBar(Map<_PointStatus, int> summary) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryChip(
              _PointStatus.good, summary[_PointStatus.good] ?? 0),
          _buildSummaryChip(
              _PointStatus.warning, summary[_PointStatus.warning] ?? 0),
          _buildSummaryChip(
              _PointStatus.bad, summary[_PointStatus.bad] ?? 0),
          Text("รวม ${_points.length} จุด",
              style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildSummaryChip(_PointStatus status, int count) {
    return Row(
      children: [
        Icon(_statusIcon(status), color: _statusColor(status), size: 18),
        const SizedBox(width: 4),
        Text("$count จุด",
            style: TextStyle(
                color: _statusColor(status),
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      ],
    );
  }

  // ─── รายการจุด ───
  Widget _buildPointList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 20),
      itemCount: _points.length,
      itemBuilder: (ctx, i) {
        final p = _points[i];
        final status = _evaluatePoint(p);
        final color = _statusColor(status);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color.withOpacity(0.5), width: 1.5),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withOpacity(0.15),
              child: Text("${i + 1}",
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold)),
            ),
            title: Row(
              children: [
                Icon(_statusIcon(status), color: color, size: 16),
                const SizedBox(width: 4),
                Text(_statusLabel(status),
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(_formatDateTime(p.timestamp),
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey)),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  _buildMiniNPK("N", p.n, _expectedN, Colors.blue),
                  const SizedBox(width: 8),
                  _buildMiniNPK("P", p.p, _expectedP, Colors.green[700]!),
                  const SizedBox(width: 8),
                  _buildMiniNPK("K", p.k, _expectedK, Colors.orange[800]!),
                  const Spacer(),
                  Icon(Icons.water_drop,
                      size: 13, color: Colors.blue[300]),
                  Text(" ${p.moisture}%",
                      style: TextStyle(
                          fontSize: 12, color: Colors.blue[400])),
                ],
              ),
            ),
            onTap: () => _showPointDetail(p, status),
          ),
        );
      },
    );
  }

  Widget _buildMiniNPK(String label, int value, int expected, Color color) {
    String diff = expected > 0
        ? (value >= expected
            ? "+${value - expected}"
            : "${value - expected}")
        : "";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.bold)),
        Row(
          children: [
            Text("$value",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: color)),
            if (diff.isNotEmpty)
              Text(" ($diff)",
                  style: TextStyle(
                      fontSize: 10,
                      color: diff.startsWith('+')
                          ? Colors.green
                          : Colors.red)),
          ],
        ),
      ],
    );
  }

  // ─── popup รายละเอียดจุด ───
  void _showPointDetail(_PointData p, _PointStatus status) {
    final color = _statusColor(status);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_statusIcon(status), color: color, size: 26),
                  const SizedBox(width: 10),
                  Text("สถานะ: ${_statusLabel(status)}",
                      style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              Text(_formatDateTime(p.timestamp),
                  style:
                      const TextStyle(fontSize: 13, color: Colors.grey)),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildDetailBox("N", p.n, _expectedN, Colors.blue),
                  _buildDetailBox("P", p.p, _expectedP,
                      Colors.green[700]!),
                  _buildDetailBox(
                      "K", p.k, _expectedK, Colors.orange[800]!),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.water_drop,
                      color: Colors.blue, size: 20),
                  const SizedBox(width: 6),
                  Text("ความชื้น: ${p.moisture}%",
                      style: const TextStyle(fontSize: 16)),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                    "พิกัด: ${p.lat.toStringAsFixed(6)}, ${p.lng.toStringAsFixed(6)}",
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailBox(
      String label, int value, int expected, Color color) {
    double ratio = expected > 0 ? value / expected : 1.0;
    String ratioStr =
        expected > 0 ? "${(ratio * 100).toStringAsFixed(0)}%" : "-";

    return Column(
      children: [
        Text(label,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        const SizedBox(height: 4),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Column(
            children: [
              Text("$value",
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Text("คาดหวัง: $expected",
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey)),
              Text(ratioStr,
                  style: TextStyle(
                      fontSize: 12,
                      color:
                          ratio >= 0.8 && ratio <= 1.2
                              ? Colors.green
                              : Colors.red,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────
enum _PointStatus { good, warning, bad, neutral }

class _PointData {
  final String id;
  final double lat;
  final double lng;
  final int n;
  final int p;
  final int k;
  final int moisture;
  final Timestamp? timestamp;
  final String source;

  _PointData({
    required this.id,
    required this.lat,
    required this.lng,
    required this.n,
    required this.p,
    required this.k,
    required this.moisture,
    required this.timestamp,
    required this.source,
  });
}