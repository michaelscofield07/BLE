import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';

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

    // Load device ID asynchronously but guard context
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
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  // Capture dependencies BEFORE async gaps
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
