import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ble_service.dart';

Future<void> showBluetoothScanDialog({
  required BuildContext context,
  required VoidCallback onConnected,
  required VoidCallback onDisconnected,
}) async {
  await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.location,
  ].request();

  final List<BluetoothDevice> bonded = await FlutterBluePlus.bondedDevices;

  if (!context.mounted) return;

  await showDialog(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) => BluetoothDialog(
      homeContext: context,
      bonded: bonded,
      onConnected: onConnected,
      onDisconnected: onDisconnected,
    ),
  );
}

class BluetoothDialog extends StatelessWidget {
  final BuildContext homeContext;
  final List<BluetoothDevice> bonded;
  final VoidCallback onConnected;
  final VoidCallback onDisconnected;

  const BluetoothDialog({
    super.key,
    required this.homeContext,
    required this.bonded,
    required this.onConnected,
    required this.onDisconnected,
  });

  Future<void> _connect(BuildContext dialogContext, BluetoothDevice device) async {
    Navigator.of(dialogContext, rootNavigator: true).pop();

    showDialog(
      context: homeContext,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await BLEService().connect(device);
      if (homeContext.mounted) {
        Navigator.of(homeContext, rootNavigator: true).pop();
        onConnected();
        ScaffoldMessenger.of(homeContext).showSnackBar(
          const SnackBar(
              content: Text("เชื่อมต่อสำเร็จ"),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (homeContext.mounted) {
        Navigator.of(homeContext, rootNavigator: true).pop();
        onDisconnected();
        ScaffoldMessenger.of(homeContext).showSnackBar(
          SnackBar(
              content: Text("เชื่อมต่อไม่ได้: $e"),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.bluetooth, color: Colors.blue),
          SizedBox(width: 10),
          Text("เชื่อมต่ออุปกรณ์ NPK", style: TextStyle(fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: bonded.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bluetooth_disabled,
                        size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      "ไม่มีอุปกรณ์ที่จับคู่ไว้\nกรุณา Pair อุปกรณ์ในการตั้งค่า\nBluetooth ของโทรศัพท์ก่อน",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: bonded.length,
                itemBuilder: (ctx, i) {
                  final device = bonded[i];
                  return ListTile(
                    leading: const Icon(Icons.bluetooth, color: Colors.blue),
                    title: Text(
                      device.platformName.isNotEmpty
                          ? device.platformName
                          : "Unknown Device",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(device.remoteId.toString()),
                    trailing: ElevatedButton(
                      onPressed: () => _connect(context, device),
                      child: const Text("เชื่อมต่อ"),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text("ปิด"),
        ),
      ],
    );
  }
}