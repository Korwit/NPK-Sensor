import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';

// ─────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────
class ChartPointData {
  final int index;
  final int n, p, k, moisture;
  final DateTime? timestamp;

  const ChartPointData({
    required this.index,
    required this.n,
    required this.p,
    required this.k,
    required this.moisture,
    this.timestamp,
  });
}

enum MenuOption { bar, line, radar, pdf }

// ─────────────────────────────────────────────
// Entry point — popup menu
// ─────────────────────────────────────────────
Future<void> showChartMenu({
  required BuildContext context,
  required List<ChartPointData> points,
  required int expectedN,
  required int expectedP,
  required int expectedK,
  required double tolerance,
  required List<String> fertilizerAdvices,
  required double avgN,
  required double avgP,
  required double avgK,
  required String aiAnalysisText,
}) async {
  final RenderBox button = context.findRenderObject() as RenderBox;
  final RenderBox overlay =
      Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
  final RelativeRect position = RelativeRect.fromRect(
    Rect.fromPoints(
      button.localToGlobal(Offset.zero, ancestor: overlay),
      button.localToGlobal(button.size.bottomRight(Offset.zero),
          ancestor: overlay),
    ),
    Offset.zero & overlay.size,
  );

  final MenuOption? selected = await showMenu<MenuOption>(
    context: context,
    position: position,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    items: const [
      PopupMenuItem(
        value: MenuOption.bar,
        child: Row(children: [Icon(Icons.bar_chart, color: Colors.teal, size: 20), SizedBox(width: 10), Text("Bar Chart (เปรียบเทียบ)")]),
      ),
      PopupMenuItem(
        value: MenuOption.line,
        child: Row(children: [Icon(Icons.show_chart, color: Colors.blue, size: 20), SizedBox(width: 10), Text("Line Chart (แนวโน้ม)")]),
      ),
      PopupMenuItem(
        value: MenuOption.radar,
        child: Row(children: [Icon(Icons.radar, color: Colors.deepPurple, size: 20), SizedBox(width: 10), Text("Radar Chart (สมดุล)")]),
      ),
      PopupMenuDivider(),
      PopupMenuItem(
        value: MenuOption.pdf,
        child: Row(children: [Icon(Icons.picture_as_pdf, color: Colors.red, size: 20), SizedBox(width: 10), Text("ส่งออกรายงาน PDF", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))]),
      ),
    ],
  );

  if (selected == null || !context.mounted) return;

  if (selected == MenuOption.pdf) {
    await _exportFullPDF(context, points, expectedN, expectedP, expectedK, avgN, avgP, avgK, fertilizerAdvices, aiAnalysisText);
    return;
  }

  showDialog(
    context: context,
    builder: (_) => ChartDialog(
      chartType: selected,
      points: points,
      expectedN: expectedN, expectedP: expectedP, expectedK: expectedK,
      tolerance: tolerance,
      avgN: avgN, avgP: avgP, avgK: avgK,
    ),
  );
}

// ─────────────────────────────────────────────
// 📄 ฟังก์ชันสร้าง PDF (แบบมีกราฟ + AI)
// ─────────────────────────────────────────────
Future<void> _exportFullPDF(
  BuildContext context, List<ChartPointData> points, 
  int expN, int expP, int expK, 
  double avgN, double avgP, double avgK, 
  List<String> advices, String aiText
) async {
  
  showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

  try {
    final pdf = pw.Document();
    final fontRegular = await PdfGoogleFonts.sarabunRegular();
    final fontBold = await PdfGoogleFonts.sarabunBold();
    final theme = pw.ThemeData.withFont(base: fontRegular, bold: fontBold);

    double maxVal = 100;
    for (var p in points) {
      if (p.n > maxVal) maxVal = p.n.toDouble();
      if (p.p > maxVal) maxVal = p.p.toDouble();
      if (p.k > maxVal) maxVal = p.k.toDouble();
    }
    maxVal = ((maxVal / 50).ceil() * 50).toDouble();

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          theme: theme,
        ),
        build: (ctx) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(color: PdfColors.teal, borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("รายงานวิเคราะห์ค่าดิน NPK", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                pw.SizedBox(height: 4),
                pw.Text("วันที่ออกรายงาน: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}", style: const pw.TextStyle(fontSize: 11, color: PdfColors.white)),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 3,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("สรุปค่าเฉลี่ยทั้งแปลง", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 8),
                    _pdfSummaryTable(avgN, avgP, avgK, expN, expP, expK),
                  ]
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                flex: 2,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text("ความสมดุลธาตุอาหาร (Radar)", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 8),
                    _pdfRadarChart(avgN, avgP, avgK, expN, expP, expK),
                  ]
                ),
              ),
            ]
          ),
          pw.SizedBox(height: 16),

          pw.Text("วิเคราะห์โดยนักวิชาการเกษตร AI", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.deepPurple)),
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(8), border: pw.Border.all(color: PdfColors.grey300)),
            child: pw.Text(aiText, style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.5)),
          ),
          pw.SizedBox(height: 16),

          pw.Text("คำแนะนำการจัดการปุ๋ยเบื้องต้น", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.green)),
          pw.SizedBox(height: 8),
          if (advices.isEmpty)
              pw.Text("- ค่าดินอยู่ในเกณฑ์ปกติ ไม่จำเป็นต้องปรับปรุง", style: const pw.TextStyle(color: PdfColors.green, fontSize: 11))
          else
            ...advices.map((a) => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 4), child: pw.Text("• $a", style: const pw.TextStyle(fontSize: 11)))),

          pw.SizedBox(height: 30),
          pw.Divider(),
          pw.SizedBox(height: 16),

          pw.Text("เปรียบเทียบปริมาณ NPK แต่ละจุด (Bar Chart)", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          _pdfBarChart(points, maxVal),
          pw.SizedBox(height: 20),

          pw.Text("แนวโน้มและพฤติกรรมในแปลง (Line Chart)", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          _pdfLineChart(points, maxVal),
          pw.SizedBox(height: 20),

          pw.Text("ข้อมูลจุดตรวจ", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          _pdfPointsTable(points),
        ],
      ),
    );

    final bytes = await pdf.save();
    if (context.mounted) Navigator.pop(context); 
    
    final fileName = "soil_report_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf";
    
    final xFile = XFile.fromData(
      bytes,
      name: fileName,
      mimeType: 'application/pdf',
    );
    
    await Share.shareXFiles([xFile], text: 'รายงานวิเคราะห์ค่าดิน NPK: $fileName');

  } catch (e) {
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export ไม่สำเร็จ: $e")));
    }
  }
}

// ---- ส่วนประกอบการวาด PDF ----
pw.Widget _pdfSummaryTable(double avgN, double avgP, double avgK, int expN, int expP, int expK) {
  pw.Widget cell(String t, {bool b = false}) => pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(t, style: pw.TextStyle(fontSize: 10, fontWeight: b ? pw.FontWeight.bold : null)));
  
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey),
    children: [
      pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.teal50), children: [cell("ธาตุ", b:true), cell("เฉลี่ย", b:true), cell("คาดหวัง", b:true)]),
      pw.TableRow(children: [cell("N (ไนโตรเจน)"), cell(avgN.toStringAsFixed(1)), cell("$expN")]),
      pw.TableRow(children: [cell("P (ฟอสฟอรัส)"), cell(avgP.toStringAsFixed(1)), cell("$expP")]),
      pw.TableRow(children: [cell("K (โพแทสเซียม)"), cell(avgK.toStringAsFixed(1)), cell("$expK")]),
    ],
  );
}

pw.Widget _pdfPointsTable(List<ChartPointData> points) {
  pw.Widget cell(String t, {bool b = false}) => pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(t, style: pw.TextStyle(fontSize: 10, fontWeight: b ? pw.FontWeight.bold : null), textAlign: pw.TextAlign.center));
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey),
    children: [
      pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.teal50), children: [cell("จุดที่", b:true), cell("N", b:true), cell("P", b:true), cell("K", b:true), cell("ชื้น%", b:true)]),
      ...points.map((p) => pw.TableRow(children: [cell("${p.index + 1}"), cell("${p.n}"), cell("${p.p}"), cell("${p.k}"), cell("${p.moisture}%")])),
    ],
  );
}

pw.Widget _pdfBarChart(List<ChartPointData> points, double maxVal) {
  final xAxis = points.map((p) => p.index.toDouble() + 1).toList();
  final List<double> yAxis = List.generate(6, (i) => (maxVal / 5) * i);

  return pw.Container(
    height: 160,
    child: pw.Chart(
      grid: pw.CartesianGrid(xAxis: pw.FixedAxis(xAxis), yAxis: pw.FixedAxis(yAxis)),
      datasets: [
        pw.BarDataSet(color: PdfColors.blue, width: 4, data: points.map((p) => pw.PointChartValue(p.index.toDouble() + 1 - 0.2, p.n.toDouble())).toList()),
        pw.BarDataSet(color: PdfColors.green, width: 4, data: points.map((p) => pw.PointChartValue(p.index.toDouble() + 1, p.p.toDouble())).toList()),
        pw.BarDataSet(color: PdfColors.orange, width: 4, data: points.map((p) => pw.PointChartValue(p.index.toDouble() + 1 + 0.2, p.k.toDouble())).toList()),
      ],
    ),
  );
}

pw.Widget _pdfLineChart(List<ChartPointData> points, double maxVal) {
  final xAxis = points.map((p) => p.index.toDouble() + 1).toList();
  final List<double> yAxis = List.generate(6, (i) => (maxVal / 5) * i);

  return pw.Container(
    height: 160,
    child: pw.Chart(
      grid: pw.CartesianGrid(xAxis: pw.FixedAxis(xAxis), yAxis: pw.FixedAxis(yAxis)),
      datasets: [
        pw.LineDataSet(color: PdfColors.blue, drawPoints: true, data: points.map((p) => pw.PointChartValue(p.index.toDouble() + 1, p.n.toDouble())).toList()),
        pw.LineDataSet(color: PdfColors.green, drawPoints: true, data: points.map((p) => pw.PointChartValue(p.index.toDouble() + 1, p.p.toDouble())).toList()),
        pw.LineDataSet(color: PdfColors.orange, drawPoints: true, data: points.map((p) => pw.PointChartValue(p.index.toDouble() + 1, p.k.toDouble())).toList()),
      ],
    ),
  );
}

pw.Widget _pdfRadarChart(double avgN, double avgP, double avgK, int expN, int expP, int expK) {
  return pw.SizedBox(
    width: 120, height: 120,
    child: pw.Stack(
      alignment: pw.Alignment.center,
      children: [
        pw.CustomPaint(
          size: const PdfPoint(100, 100),
          painter: (PdfGraphics canvas, PdfPoint size) {
            final cx = size.x / 2, cy = size.y / 2;
            final r = 40.0;
            for(int i=0; i<3; i++) {
               final angle = -math.pi/2 + i * 2 * math.pi / 3;
               canvas.drawLine(cx, cy, cx + r * math.cos(angle), cy + r * math.sin(angle));
               canvas.setStrokeColor(PdfColors.grey300);
               canvas.strokePath();
            }
            canvas.moveTo(cx + r*(100/150)*math.cos(-math.pi/2), cy + r*(100/150)*math.sin(-math.pi/2));
            canvas.lineTo(cx + r*(100/150)*math.cos(-math.pi/2 + 2*math.pi/3), cy + r*(100/150)*math.sin(-math.pi/2 + 2*math.pi/3));
            canvas.lineTo(cx + r*(100/150)*math.cos(-math.pi/2 + 4*math.pi/3), cy + r*(100/150)*math.sin(-math.pi/2 + 4*math.pi/3));
            canvas.closePath();
            canvas.setStrokeColor(PdfColors.grey);
            canvas.strokePath();

            double nR = expN > 0 ? (avgN / expN) * 100 : 100;
            double pR = expP > 0 ? (avgP / expP) * 100 : 100;
            double kR = expK > 0 ? (avgK / expK) * 100 : 100;
            nR = math.min(nR, 150); pR = math.min(pR, 150); kR = math.min(kR, 150);

            final nx = cx + r * (nR/150) * math.cos(-math.pi/2);
            final ny = cy + r * (nR/150) * math.sin(-math.pi/2);
            final px = cx + r * (pR/150) * math.cos(-math.pi/2 + 2*math.pi/3);
            final py = cy + r * (pR/150) * math.sin(-math.pi/2 + 2*math.pi/3);
            final kx = cx + r * (kR/150) * math.cos(-math.pi/2 + 4*math.pi/3);
            final ky = cy + r * (kR/150) * math.sin(-math.pi/2 + 4*math.pi/3);

            canvas.moveTo(nx, ny); canvas.lineTo(px, py); canvas.lineTo(kx, ky); canvas.closePath();
            canvas.setFillColor(PdfColor.fromInt(0x44008080));
            canvas.fillPath();
            canvas.moveTo(nx, ny); canvas.lineTo(px, py); canvas.lineTo(kx, ky); canvas.closePath();
            canvas.setStrokeColor(PdfColors.teal);
            canvas.strokePath();
          }
        ),
        pw.Positioned(top: 0, child: pw.Text("N", style: pw.TextStyle(color: PdfColors.blue, fontSize: 10, fontWeight: pw.FontWeight.bold))),
        pw.Positioned(bottom: 5, right: 0, child: pw.Text("P", style: pw.TextStyle(color: PdfColors.green, fontSize: 10, fontWeight: pw.FontWeight.bold))),
        pw.Positioned(bottom: 5, left: 0, child: pw.Text("K", style: pw.TextStyle(color: PdfColors.orange, fontSize: 10, fontWeight: pw.FontWeight.bold))),
      ]
    )
  );
}

// ─────────────────────────────────────────────
// ChartDialog (สำหรับการแสดงผลบนหน้าจอโทรศัพท์)
// ─────────────────────────────────────────────
class ChartDialog extends StatelessWidget {
  final MenuOption chartType;
  final List<ChartPointData> points;
  final int expectedN, expectedP, expectedK;
  final double tolerance;
  final double avgN, avgP, avgK;

  const ChartDialog({
    super.key, required this.chartType, required this.points,
    required this.expectedN, required this.expectedP, required this.expectedK,
    required this.tolerance, required this.avgN, required this.avgP, required this.avgK,
  });

  String get _title {
    if (chartType == MenuOption.bar) return "Bar Chart — N P K แต่ละจุด";
    if (chartType == MenuOption.line) return "Line Chart — แนวโน้ม N P K";
    if (chartType == MenuOption.radar) return "Radar Chart — ภาพรวม N P K";
    return "";
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            decoration: const BoxDecoration(color: Colors.teal, borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
            child: Row(
              children: [
                Expanded(child: Text(_title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
                IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 22), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SizedBox(height: 300, child: _buildChart()),
                  const SizedBox(height: 12),
                  _buildLegend(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    if (chartType == MenuOption.bar) return _buildBarChart();
    if (chartType == MenuOption.line) return _buildLineChart();
    if (chartType == MenuOption.radar) return _buildRadarChart();
    return const SizedBox();
  }

  Widget _buildBarChart() {
    final groups = points.asMap().entries.map((e) {
      final p = e.value;
      return BarChartGroupData(
        x: e.key, barsSpace: 2,
        barRods: [
          BarChartRodData(toY: p.n.toDouble(), color: Colors.blue, width: 6, borderRadius: BorderRadius.circular(3)),
          BarChartRodData(toY: p.p.toDouble(), color: Colors.green[700]!, width: 6, borderRadius: BorderRadius.circular(3)),
          BarChartRodData(toY: p.k.toDouble(), color: Colors.orange[800]!, width: 6, borderRadius: BorderRadius.circular(3)),
        ],
      );
    }).toList();

    return BarChart(BarChartData(
      barGroups: groups, gridData: const FlGridData(show: true), borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) => Text("จุด${v.toInt() + 1}", style: const TextStyle(fontSize: 9)))), topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false))),
    ));
  }

  Widget _buildLineChart() {
    List<FlSpot> nSpots = [], pSpots = [], kSpots = [];
    for (int i = 0; i < points.length; i++) {
      nSpots.add(FlSpot(i.toDouble(), points[i].n.toDouble()));
      pSpots.add(FlSpot(i.toDouble(), points[i].p.toDouble()));
      kSpots.add(FlSpot(i.toDouble(), points[i].k.toDouble()));
    }
    return LineChart(LineChartData(
      lineBarsData: [
        LineChartBarData(spots: nSpots, isCurved: true, color: Colors.blue, barWidth: 2.5, dotData: const FlDotData(show: true)),
        LineChartBarData(spots: pSpots, isCurved: true, color: Colors.green[700]!, barWidth: 2.5, dotData: const FlDotData(show: true)),
        LineChartBarData(spots: kSpots, isCurved: true, color: Colors.orange[800]!, barWidth: 2.5, dotData: const FlDotData(show: true)),
      ],
      gridData: const FlGridData(show: true), borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) => Text("จุด${v.toInt() + 1}", style: const TextStyle(fontSize: 9)))), topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false))),
    ));
  }

  Widget _buildRadarChart() {
    double norm(double val, int exp) => exp > 0 ? (val / exp * 100).clamp(0, 150) : 100;
    final avgNorm = [norm(avgN, expectedN), norm(avgP, expectedP), norm(avgK, expectedK)];

    return RadarChart(RadarChartData(
      dataSets: [
        RadarDataSet(dataEntries: avgNorm.map((v) => RadarEntry(value: v)).toList(), fillColor: Colors.teal.withOpacity(0.2), borderColor: Colors.teal, borderWidth: 2, entryRadius: 4),
        RadarDataSet(dataEntries: const [RadarEntry(value: 100), RadarEntry(value: 100), RadarEntry(value: 100)], fillColor: Colors.grey.withOpacity(0.05), borderColor: Colors.grey.withOpacity(0.5), borderWidth: 1.5, entryRadius: 2),
      ],
      radarBackgroundColor: Colors.transparent, borderData: FlBorderData(show: false), radarBorderData: const BorderSide(color: Colors.transparent), tickCount: 3,
      ticksTextStyle: const TextStyle(fontSize: 8, color: Colors.grey), tickBorderData: const BorderSide(color: Colors.grey, width: 0.5), gridBorderData: const BorderSide(color: Colors.grey, width: 0.5),
      getTitle: (index, angle) => RadarChartTitle(text: ["N\n${avgN.toStringAsFixed(1)}", "P\n${avgP.toStringAsFixed(1)}", "K\n${avgK.toStringAsFixed(1)}"][index], angle: angle),
    ));
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 16, runSpacing: 6, alignment: WrapAlignment.center,
      children: [
        _legendItem("N (ไนโตรเจน)", Colors.blue), _legendItem("P (ฟอสฟอรัส)", Colors.green[700]!), _legendItem("K (โพแทสเซียม)", Colors.orange[800]!),
        if (chartType != MenuOption.radar) _legendItem("--- ค่าคาดหวัง", Colors.grey),
      ],
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 11))],
    );
  }
}