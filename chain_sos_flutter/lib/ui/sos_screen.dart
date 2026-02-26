import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sos_service.dart';
import '../services/ble_service.dart';
import 'nearby_devices_screen.dart';
import 'intelligent_sos_screen.dart';

class SOSSreen extends StatefulWidget {
  const SOSSreen({super.key});

  @override
  State<SOSSreen> createState() => _SOSSreenState();
}

class _SOSSreenState extends State<SOSSreen> {
  bool _arming = false;
  int _remaining = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        final ble = context.read<BleService>();
        ble.startScan();
        
        // Initialize tracking state
        final sos = context.read<SosService>();
        await sos.initializeTracking();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    final ble = context.read<BleService>();
    ble.stopScan();
    super.dispose();
  }

  void _startArming() {
    if (_arming) return;
    setState(() {
      _arming = true;
      _remaining = 5;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) return;
      if (_remaining <= 1) {
        t.cancel();
        setState(() {
          _arming = false;
        });
        final sos = context.read<SosService>();
        final ble = context.read<BleService>();
        await sos.sendSOS(onOffline: (packet) async {
          ble.logs.add('Broadcasting offline ${packet.packetId}');
          await ble.advertise(packet);
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SOS sent')),
        );
      } else {
        setState(() {
          _remaining -= 1;
        });
      }
    });
  }

  void _cancelArming() {
    if (!_arming) return;
    _timer?.cancel();
    setState(() {
      _arming = false;
      _remaining = 5;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sos = context.watch<SosService>();
    final ble = context.watch<BleService>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red[700],
        title: const Row(
          children: [
            Icon(Icons.emergency, color: Colors.white),
            SizedBox(width: 8),
            Text('ChainSOS', style: TextStyle(color: Colors.white)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _arming
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const IntelligentSosScreen(),
                      ),
                    );
                  },
            icon: const Icon(Icons.psychology, color: Colors.white),
            tooltip: 'Intelligent SOS',
          ),
          IconButton(
            onPressed: _arming
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const NearbyDevicesScreen(),
                      ),
                    );
                  },
            icon: const Icon(Icons.people, color: Colors.white),
          ),
          IconButton(
            onPressed: _arming
                ? null
                : () => Navigator.pushNamed(context, '/settings'),
            icon: const Icon(Icons.settings, color: Colors.white),
          ),
          IconButton(
            onPressed: _arming
                ? null
                : () => Navigator.pushNamed(context, '/dashboard'),
            icon: const Icon(Icons.dashboard, color: Colors.white),
          ),
        ],
        elevation: 2,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('Force Internet:'),
                    Switch(
                      value: sos.forceOnline,
                      onChanged: (v) => sos.setForceOnline(v),
                    ),
                  ],
                ),
                if (_arming)
                  TextButton.icon(
                    onPressed: _cancelArming,
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    label: const Text('Cancel',
                        style: TextStyle(color: Colors.red)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Smaller SOS button
            Center(
              child: SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: CircularProgressIndicator(
                        value: _arming ? (5 - _remaining) / 5 : null,
                        strokeWidth: 8,
                        color: Colors.red[700],
                        backgroundColor: Colors.red[100],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(24),
                        backgroundColor:
                            _arming ? Colors.orange : Colors.red[700],
                        foregroundColor: Colors.white,
                        elevation: 6,
                      ),
                      onPressed: _arming ? null : _startArming,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _arming ? '$_remaining' : 'SOS',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _arming
                                ? 'Sending in...'
                                : 'Tap to start',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Expanded logs section
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.list, color: Colors.blue),
                                SizedBox(width: 8),
                                Text('SOS Logs',
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const Divider(height: 24),
                            ...sos.logs.reversed.map((e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text('• $e'),
                            )),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.bluetooth, color: Colors.indigo),
                                SizedBox(width: 8),
                                Text('BLE Logs',
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const Divider(height: 24),
                            ...ble.logs.reversed.map((e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text('• $e'),
                            )),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
