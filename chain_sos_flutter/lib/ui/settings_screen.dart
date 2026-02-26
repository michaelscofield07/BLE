import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';
import '../services/sos_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _name;
  late final TextEditingController _deviceId;
  late final TextEditingController _contacts;

  @override
  void initState() {
    super.initState();
    final s = context.read<StorageService>();
    _name = TextEditingController(text: s.name);
    _contacts = TextEditingController(text: s.contactsCsv);
    _deviceId = TextEditingController(text: '');
    s.getDeviceId().then((id) {
      if (!mounted) return;
      setState(() {
        _deviceId.text = id;
      });
    });
  }
  @override
  void dispose() {
    _name.dispose();
    _deviceId.dispose();
    _contacts.dispose();
    super.dispose();
  }

  Future<bool?> _showCancelConfirmation(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Cancel Live Tracking'),
          content: const Text(
            'Are you sure you want to cancel live tracking? This will stop sending location updates for the current SOS alert.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Yes, Cancel'),
            ),
          ],
        );
      },
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _deviceId,
              decoration: const InputDecoration(labelText: 'Device ID'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contacts,
              decoration: const InputDecoration(
                labelText: 'Emergency Contacts (comma separated)',
              ),
            ),
            const Spacer(),
            // Tracking Status Section
            Consumer<SosService>(
              builder: (context, sosService, child) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.gps_fixed,
                            color: Colors.red.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Live Tracking Status',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tracking can be stopped from this screen when an SOS is active.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final confirmed = await _showCancelConfirmation(context);
                            if (confirmed == true) {
                              try {
                                await sosService.stopLiveTracking();
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Live tracking cancelled successfully'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error cancelling tracking: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.cancel),
                          label: const Text('Cancel Live Tracking'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  final storage = context.read<StorageService>();

                  final name = _name.text.trim();
                  final contacts = _contacts.text.trim();
                  final deviceId = _deviceId.text.trim();

                  await storage.setName(name);
                  await storage.setContactsCsv(contacts);
                  if (deviceId.isNotEmpty) {
                    await storage.setDeviceId(deviceId);
                  }

                  if (!mounted) return;
                  navigator.pop();
                },
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
