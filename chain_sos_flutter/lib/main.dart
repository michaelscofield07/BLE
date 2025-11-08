import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/sos_service.dart';
import 'services/ble_service.dart';
import 'services/storage_service.dart';
import 'ui/sos_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/dashboard_screen.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _ensurePermissions();
  final storageService = await StorageService.create();
  final sosService = SosService(storageService: storageService);
  final bleService = BleService(storageService: storageService, sosService: sosService);
  runApp(ChainSOSApp(
    storageService: storageService,
    sosService: sosService,
    bleService: bleService,
  ));
}

Future<void> _ensurePermissions() async {
  final requests = <Permission>[
    Permission.location,
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothAdvertise,
    Permission.bluetoothConnect,
  ];
  for (final p in requests) {
    if (await p.status.isDenied) {
      await p.request();
    }
  }
}

class ChainSOSApp extends StatelessWidget {
  final StorageService storageService;
  final SosService sosService;
  final BleService bleService;

  const ChainSOSApp({super.key, required this.storageService, required this.sosService, required this.bleService});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: storageService),
        ChangeNotifierProvider.value(value: sosService),
        ChangeNotifierProvider.value(value: bleService),
      ],
      child: MaterialApp(
        title: 'ChainSOS',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
          useMaterial3: true,
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => const SOSSreen(),
          '/settings': (context) => const SettingsScreen(),
          '/dashboard': (context) => const DashboardScreen(),
        },
      ),
    );
  }
}