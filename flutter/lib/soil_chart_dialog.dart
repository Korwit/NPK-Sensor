import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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

enum ChartType { bar, line, radar }

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

  final ChartType? selected = await showMenu<ChartType>(
    context: context,
    position: position,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    items: const [
      PopupMenuItem(
        value: ChartType.bar,
        child: Row(children: [
          Icon(Icons.bar_chart, color: Colors.teal, size: 20),
          SizedBox(width: 10),
          Text("Bar Chart"),
        ]),
      ),
      PopupMenuItem(
        value: ChartType.line,
        child: Row(children: [
          Icon(Icons.show_chart, color: Colors.blue, size: 20),
          SizedBox(width: 10),
          Text("Line Chart"),
        ]),
      ),
      PopupMenuItem(
        value: ChartType.radar,
        child: Row(children: [
          Icon(Icons.radar, color: Colors.deepPurple, size: 20),
          SizedBox(width: 10),
          Text("Radar Chart"),
        ]),
      ),
    ],
  );

  if (selected == null || !context.mounted) return;

  showDialog(
    context: context,
    builder: (_) => ChartDialog(
      chartType: selected,
      points: points,
      expectedN: expectedN,
      expectedP: expectedP,
      expectedK: expectedK,
      tolerance: tolerance,
      fertilizerAdvices: fertilizerAdvices,
      avgN: avgN,
      avgP: avgP,
      avgK: avgK,
    ),
  );
}

// ─────────────────────────────────────────────
// ChartDialog
// ─────────────────────────────────────────────
class ChartDialog extends StatefulWidget {
  final ChartType chartType;
  final List<ChartPointData> points;
  final int expectedN, expectedP, expectedK;
  final double tolerance;
  final List<String> fertilizerAdvices;
  final double avgN, avgP, avgK;

  const ChartDialog({
    super.key,
    required this.chartType,
    required this.points,
    required this.expectedN,
    required this.expectedP,
    required this.expectedK,
    required this.tolerance,
    required this.fertilizerAdvices,
    required this.avgN,
    required this.avgP,
    required this.avgK,
  });

  @override
  State<ChartDialog> createState() => _ChartDialogState();
}

class _ChartDialogState extends State<ChartDialog> {
  bool _isExporting = false;

  // ── helpers ──────────────────────────────────
  String get _title => switch (widget.chartType) {
        ChartType.bar => "Bar Chart — N P K แต่ละจุด",
        ChartType.line => "Line Chart — แนวโน้ม N P K",
        ChartType.radar => "Radar Chart — ภาพรวม N P K",
      };

  // ─────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: const BoxDecoration(
        color: Colors.teal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          _isExporting
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.picture_as_pdf,
                      color: Colors.white, size: 22),
                  tooltip: "Export PDF",
                  onPressed: _exportPDF,
                ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 22),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Charts (UI)
  // ─────────────────────────────────────────────
  Widget _buildChart() => switch (widget.chartType) {
        ChartType.bar => _buildBarChart(),
        ChartType.line => _buildLineChart(),
        ChartType.radar => _buildRadarChart(),
      };

  Widget _buildBarChart() {
    final groups = widget.points.asMap().entries.map((e) {
      final p = e.value;
      return BarChartGroupData(
        x: e.key,
        barsSpace: 2,
        barRods: [
          _barRod(p.n.toDouble(), Colors.blue),
          _barRod(p.p.toDouble(), Colors.green[700]!),
          _barRod(p.k.toDouble(), Colors.orange[800]!),
        ],
      );
    }).toList();

    return BarChart(BarChartData(
      barGroups: groups,
      gridData: const FlGridData(show: true),
      borderData: FlBorderData(show: false),
      titlesData: _titlesData(
          bottom: (v, _) =>
              Text("จุด${v.toInt() + 1}", style: const TextStyle(fontSize: 9))),
      extraLinesData: _expectedLines(),
    ));
  }

  BarChartRodData _barRod(double y, Color color) => BarChartRodData(
        toY: y,
        color: color,
        width: 6,
        borderRadius: BorderRadius.circular(3),
      );

  Widget _buildLineChart() {
    List<FlSpot> nSpots = [], pSpots = [], kSpots = [];
    for (int i = 0; i < widget.points.length; i++) {
      nSpots.add(FlSpot(i.toDouble(), widget.points[i].n.toDouble()));
      pSpots.add(FlSpot(i.toDouble(), widget.points[i].p.toDouble()));
      kSpots.add(FlSpot(i.toDouble(), widget.points[i].k.toDouble()));
    }

    return LineChart(LineChartData(
      lineBarsData: [
        _lineBar(nSpots, Colors.blue),
        _lineBar(pSpots, Colors.green[700]!),
        _lineBar(kSpots, Colors.orange[800]!),
      ],
      gridData: const FlGridData(show: true),
      borderData: FlBorderData(show: false),
      titlesData: _titlesData(
          bottom: (v, _) =>
              Text("จุด${v.toInt() + 1}", style: const TextStyle(fontSize: 9))),
      extraLinesData: _expectedLines(showLabels: true),
    ));
  }

  LineChartBarData _lineBar(List<FlSpot> spots, Color color) =>
      LineChartBarData(
        spots: spots,
        isCurved: true,
        color: color,
        barWidth: 2.5,
        dotData: FlDotData(
          getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
            radius: 4,
            color: color,
            strokeColor: Colors.white,
            strokeWidth: 1.5,
          ),
        ),
        belowBarData: BarAreaData(show: true, color: color.withOpacity(0.08)),
      );

  Widget _buildRadarChart() {
    double norm(double val, int exp) =>
        exp > 0 ? (val / exp * 100).clamp(0, 150) : 100;

    final avgNorm = [
      norm(widget.avgN, widget.expectedN),
      norm(widget.avgP, widget.expectedP),
      norm(widget.avgK, widget.expectedK),
    ];

    return RadarChart(RadarChartData(
      dataSets: [
        RadarDataSet(
          dataEntries: avgNorm.map((v) => RadarEntry(value: v)).toList(),
          fillColor: Colors.teal.withOpacity(0.2),
          borderColor: Colors.teal,
          borderWidth: 2,
          entryRadius: 4,
        ),
        RadarDataSet(
          dataEntries: const [
            RadarEntry(value: 100),
            RadarEntry(value: 100),
            RadarEntry(value: 100),
          ],
          fillColor: Colors.grey.withOpacity(0.05),
          borderColor: Colors.grey.withOpacity(0.5),
          borderWidth: 1.5,
          entryRadius: 2,
        ),
      ],
      radarBackgroundColor: Colors.transparent,
      borderData: FlBorderData(show: false),
      radarBorderData: const BorderSide(color: Colors.transparent),
      tickCount: 3,
      ticksTextStyle: const TextStyle(fontSize: 8, color: Colors.grey),
      tickBorderData: const BorderSide(color: Colors.grey, width: 0.5),
      gridBorderData: const BorderSide(color: Colors.grey, width: 0.5),
      getTitle: (index, angle) {
        final labels = [
          "N\n${widget.avgN.toStringAsFixed(1)}",
          "P\n${widget.avgP.toStringAsFixed(1)}",
          "K\n${widget.avgK.toStringAsFixed(1)}",
        ];
        return RadarChartTitle(text: labels[index], angle: angle);
      },
    ));
  }

  FlTitlesData _titlesData(
          {required Widget Function(double, TitleMeta) bottom}) =>
      FlTitlesData(
        bottomTitles:
            AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: bottom)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            getTitlesWidget: (v, _) =>
                Text(v.toInt().toString(), style: const TextStyle(fontSize: 9)),
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      );

  ExtraLinesData _expectedLines({bool showLabels = false}) {
    HorizontalLine hLine(double y, Color color, String label) =>
        HorizontalLine(
          y: y,
          color: color.withOpacity(0.4),
          strokeWidth: 1,
          dashArray: [4, 4],
          label: showLabels
              ? HorizontalLineLabel(
                  show: true,
                  labelResolver: (_) => label,
                  style: TextStyle(fontSize: 9, color: color),
                )
              : null,
        );

    return ExtraLinesData(horizontalLines: [
      if (widget.expectedN > 0)
        hLine(widget.expectedN.toDouble(), Colors.blue, "N คาดหวัง"),
      if (widget.expectedP > 0)
        hLine(widget.expectedP.toDouble(), Colors.green, "P คาดหวัง"),
      if (widget.expectedK > 0)
        hLine(widget.expectedK.toDouble(), Colors.orange, "K คาดหวัง"),
    ]);
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        _legendItem("N (ไนโตรเจน)", Colors.blue),
        _legendItem("P (ฟอสฟอรัส)", Colors.green[700]!),
        _legendItem("K (โพแทสเซียม)", Colors.orange[800]!),
        if (widget.chartType != ChartType.radar)
          _legendItem("--- ค่าคาดหวัง", Colors.grey),
      ],
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // PDF Export
  // ─────────────────────────────────────────────
  Future<void> _exportPDF() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    final fileName =
        "soil_report_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf";

    try {
      final pdf = await _buildPdf();
      final bytes = await pdf.save();

      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Export ไม่สำเร็จ: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ─────────────────────────────────────────────
  // Build PDF document
  // ─────────────────────────────────────────────
  Future<pw.Document> _buildPdf() async {
    final pdf = pw.Document();

    final fontRegular = await PdfGoogleFonts.sarabunRegular();
    final fontBold = await PdfGoogleFonts.sarabunBold();

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          theme: pw.ThemeData.withFont(
            base: fontRegular,
            bold: fontBold,
          ),
        ),
        build: (ctx) => [
          _pdfHeader(),
          pw.SizedBox(height: 16),
          _pdfSectionTitle("สรุปค่าเฉลี่ยทั้งแปลง"),
          pw.SizedBox(height: 8),
          _pdfSummaryTable(),
          pw.SizedBox(height: 16),
          
          _pdfSectionTitle("กราฟแนวโน้ม NPK แต่ละจุด"),
          pw.SizedBox(height: 8),
          _pdfTrendChart(),
          pw.SizedBox(height: 16),

          _pdfSectionTitle("ข้อมูลรายจุดตรวจ"),
          pw.SizedBox(height: 8),
          _pdfPointsTable(),
          pw.SizedBox(height: 16),
          _pdfSectionTitle("คำแนะนำปุ๋ย"),
          pw.SizedBox(height: 8),
          _pdfFertilizerSection(),
          pw.SizedBox(height: 20),
          pw.Divider(),
          pw.Text(
            "* ปริมาณปุ๋ยเป็นค่าประมาณเบื้องต้น ควรปรึกษานักวิชาการเกษตรก่อนใช้จริง",
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
          ),
        ],
      ),
    );

    return pdf;
  }

  pw.Widget _pdfHeader() => pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.teal,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              "รายงานวิเคราะห์ค่าดิน NPK",
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              "วันที่ออกรายงาน: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}",
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.white),
            ),
          ],
        ),
      );

  pw.Widget _pdfSectionTitle(String title) => pw.Text(
        title,
        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
      );

  pw.Widget _pdfSummaryTable() => pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey),
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.teal50),
            children: [
              _pdfCell("ธาตุ", bold: true),
              _pdfCell("ค่าเฉลี่ย (mg/kg)", bold: true),
              _pdfCell("ค่าคาดหวัง (mg/kg)", bold: true),
              _pdfCell("% เทียบคาดหวัง", bold: true),
              _pdfCell("สถานะ", bold: true),
            ],
          ),
          _npkRow("N (ไนโตรเจน)", widget.avgN, widget.expectedN),
          _npkRow("P (ฟอสฟอรัส)", widget.avgP, widget.expectedP),
          _npkRow("K (โพแทสเซียม)", widget.avgK, widget.expectedK),
        ],
      );

  // วาดกราฟเส้นลงใน PDF (แก้ไขแกน X และ Y ให้ถูกต้อง)
  pw.Widget _pdfTrendChart() {
    // กำหนดสเกลแกน X ตามจำนวนจุด
    final xTicks = widget.points.map((p) => p.index.toDouble() + 1).toList();

    return pw.Container(
      height: 180,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis(xTicks),
          yAxis: pw.FixedAxis([0, 50, 100, 150, 200, 250, 300]),
        ),
        datasets: [
          pw.LineDataSet(
            legend: 'N',
            drawSurface: false,
            drawPoints: true,
            color: PdfColors.blue,
            data: widget.points
                .map((p) => pw.PointChartValue(p.index.toDouble() + 1, p.n.toDouble()))
                .toList(),
          ),
          pw.LineDataSet(
            legend: 'P',
            drawSurface: false,
            drawPoints: true,
            color: PdfColors.green,
            data: widget.points
                .map((p) => pw.PointChartValue(p.index.toDouble() + 1, p.p.toDouble()))
                .toList(),
          ),
          pw.LineDataSet(
            legend: 'K',
            drawSurface: false,
            drawPoints: true,
            color: PdfColors.orange,
            data: widget.points
                .map((p) => pw.PointChartValue(p.index.toDouble() + 1, p.k.toDouble()))
                .toList(),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfPointsTable() => pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey),
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.teal50),
            children: [
              _pdfCell("จุดที่", bold: true),
              _pdfCell("N", bold: true),
              _pdfCell("P", bold: true),
              _pdfCell("K", bold: true),
              _pdfCell("ความชื้น%", bold: true),
              _pdfCell("เวลา", bold: true),
            ],
          ),
          ...widget.points.map(
            (p) => pw.TableRow(children: [
              _pdfCell("${p.index + 1}"),
              _pdfCell("${p.n}"),
              _pdfCell("${p.p}"),
              _pdfCell("${p.k}"),
              _pdfCell("${p.moisture}%"),
              _pdfCell(p.timestamp != null
                  ? DateFormat('dd/MM HH:mm').format(p.timestamp!)
                  : "-"),
            ]),
          ),
        ],
      );

  pw.Widget _pdfFertilizerSection() {
    if (widget.fertilizerAdvices.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.green50,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Text(
          "ค่าดิน N P K อยู่ในเกณฑ์ปกติทั้งหมด ไม่จำเป็นต้องปรับปรุงในรอบนี้",
          style: const pw.TextStyle(color: PdfColors.green),
        ),
      );
    }

    return pw.Column(
      children: widget.fertilizerAdvices
          .map(
            (advice) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.orange50,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: PdfColors.orange, width: 1),
                ),
                child: pw.Text(advice,
                    style: const pw.TextStyle(fontSize: 11)),
              ),
            ),
          )
          .toList(),
    );
  }

  // ─────────────────────────────────────────────
  // PDF helpers
  // ─────────────────────────────────────────────
  pw.Widget _pdfCell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Text(
          text,
          style: bold
              ? pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)
              : const pw.TextStyle(fontSize: 10),
        ),
      );

  pw.TableRow _npkRow(String label, double avg, int expected) {
    final ratio = expected > 0 ? avg / expected * 100 : 0.0;
    final status = expected == 0
        ? "-"
        : ratio >= 80 && ratio <= 120
            ? "ปกติ"
            : ratio < 80
                ? "ต่ำกว่าเกณฑ์"
                : "สูงกว่าเกณฑ์";

    return pw.TableRow(children: [
      _pdfCell(label),
      _pdfCell(avg.toStringAsFixed(1)),
      _pdfCell("$expected"),
      _pdfCell("${ratio.toStringAsFixed(0)}%"),
      _pdfCell(status),
    ]);
  }
}