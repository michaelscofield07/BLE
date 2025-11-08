import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'storage_service.dart';
import 'sos_service.dart';

class BleService extends ChangeNotifier {
  final StorageService storageService;
  final SosService sosService;
  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();

  final List<String> logs = <String>[];
  bool scanning = false;
  bool advertising = false;

  BleService({required this.storageService, required this.sosService});

  // Manufacturer ID used for our payload (choose your own; 0x1337 here for demo)
  static const int _manufacturerId = 0x1337;

  List<int> _encodePayload(SosPacket p, String deviceId) {
    final int ts30 = (p.roundedTs ~/ 30).clamp(0, 0xFFFFFFFF);
    final int latI = ((p.lat + 90.0) * 10000).round().clamp(0, 0xFFFFFF);
    final int lonI = ((p.lon + 180.0) * 10000).round().clamp(0, 0xFFFFFF);
    final idBytesFull = utf8.encode(deviceId);
    // Limit ID to 13 bytes to accommodate 4-byte timestamp and stay compact
    final List<int> idBytes = idBytesFull.length > 13
        ? idBytesFull.sublist(0, 13)
        : idBytesFull;
    final idLen = idBytes.length.clamp(0, 255);
    return <int>[
      0x02,
      (ts30 >> 24) & 0xFF,
      (ts30 >> 16) & 0xFF,
      (ts30 >> 8) & 0xFF,
      ts30 & 0xFF,
      (latI >> 16) & 0xFF,
      (latI >> 8) & 0xFF,
      latI & 0xFF,
      (lonI >> 16) & 0xFF,
      (lonI >> 8) & 0xFF,
      lonI & 0xFF,
      idLen,
      ...idBytes,
    ];
  }

  ({int ts30, double lat, double lon, String senderId})? _decodePayload(
      List<int> bytes) {
    if (bytes.isEmpty) return null;
    final ver = bytes[0];
    if (ver == 0x01) {
      if (bytes.length < 11) return null;
      final int ts30 = (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
      final int latI = (bytes[4] << 16) | (bytes[5] << 8) | bytes[6];
      final int lonI = (bytes[7] << 16) | (bytes[8] << 8) | bytes[9];
      final int idLen = bytes[10];
      if (bytes.length < 11 + idLen) return null;
      final idBytes = bytes.sublist(11, 11 + idLen);
      final senderId = utf8.decode(idBytes);
      final double lat = (latI / 10000.0) - 90.0;
      final double lon = (lonI / 10000.0) - 180.0;
      return (ts30: ts30, lat: lat, lon: lon, senderId: senderId);
    } else if (ver == 0x02) {
      if (bytes.length < 12) return null;
      final int ts30 = (bytes[1] << 24) | (bytes[2] << 16) | (bytes[3] << 8) | bytes[4];
      final int latI = (bytes[5] << 16) | (bytes[6] << 8) | bytes[7];
      final int lonI = (bytes[8] << 16) | (bytes[9] << 8) | bytes[10];
      final int idLen = bytes[11];
      if (bytes.length < 12 + idLen) return null;
      final idBytes = bytes.sublist(12, 12 + idLen);
      final senderId = utf8.decode(idBytes);
      final double lat = (latI / 10000.0) - 90.0;
      final double lon = (lonI / 10000.0) - 180.0;
      return (ts30: ts30, lat: lat, lon: lon, senderId: senderId);
    } else {
      return null;
    }
  }

  StreamSubscription<List<ScanResult>>? _scanSub;

  Future<bool> _ensureBlePermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  Future<void> startScan() async {
    if (scanning) return;
    final ok = await _ensureBlePermissions();
    if (!ok) {
      logs.add('BLE permissions denied');
      notifyListeners();
      return;
    }
    scanning = true;
    logs.add('BLE scan started');
    notifyListeners();

    await FlutterBluePlus.startScan();
    _scanSub = FlutterBluePlus.scanResults.listen((results) async {
      for (final r in results) {
        final adv = r.advertisementData;
        if (adv.manufacturerData.containsKey(_manufacturerId)) {
          final bytes = adv.manufacturerData[_manufacturerId]!;
          final decoded = _decodePayload(bytes);
          if (decoded == null) continue;
          // Skip packets that originated from this device to prevent echo loops
          final myId = await storageService.getDeviceId();
          if (decoded.senderId == myId) {
            continue;
          }
          final roundedTs = decoded.ts30 * 30;
          final packetId = '${decoded.senderId}-$roundedTs';
          final seen = await storageService.hasSeenPacket(packetId);
          if (!seen) {
            logs.add('Received BLE packet $packetId');
            await storageService.rememberPacket(packetId, ttlMinutes: 10);
            final p = SosPacket(
              packetId: packetId,
              deviceId: decoded.senderId,
              roundedTs: roundedTs,
              lat: decoded.lat,
              lon: decoded.lon,
              message: 'SOS',
            );
            // Try to forward to server with retry; ignore final failure
            try {
              await sosService.sendPacketOnlineWithRetry(p);
            } catch (_) {}
            // Rebroadcast in background regardless
            unawaited(rebroadcast(p));
            notifyListeners();
          }
        }
      }
    });
  }

  Future<void> stopScan() async {
    if (!scanning) return;
    await _scanSub?.cancel();
    await FlutterBluePlus.stopScan();
    scanning = false;
    logs.add('BLE scan stopped');
    notifyListeners();
  }

  Future<void> advertise(SosPacket packet) async {
    if (advertising) return;
    if (!Platform.isAndroid) {
      logs.add('BLE advertising is only supported on Android builds.');
      notifyListeners();
      return;
    }
    final ok = await _ensureBlePermissions();
    if (!ok) {
      logs.add('BLE permissions denied');
      notifyListeners();
      return;
    }
    advertising = true;
    final deviceId = await storageService.getDeviceId();
    final payload = _encodePayload(packet, deviceId);
    logs.add('Advertising ${packet.packetId}');
    notifyListeners();

    try {
      // Mark our own packet as seen to avoid reprocessing our rebroadcasts
      await storageService.rememberPacket(packet.packetId, ttlMinutes: 10);
      await _blePeripheral.start(
        advertiseData: AdvertiseData(
          includeDeviceName: false,
          manufacturerId: _manufacturerId,
          manufacturerData: Uint8List.fromList(payload),
        ),
        advertiseSettings: AdvertiseSettings(
          advertiseMode: AdvertiseMode.advertiseModeLowLatency,
          txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
          connectable: false,
          timeout: 0,
        ),
      );
      await Future.delayed(const Duration(seconds: 20));
      await _blePeripheral.stop();
      advertising = false;
      logs.add('Advertising finished ${packet.packetId}');
      notifyListeners();
    } catch (e) {
      advertising = false;
      logs.add('Advertising failed: $e');
      notifyListeners();
    }
  }

  Future<void> rebroadcast(SosPacket packet) async {
    logs.add('Rebroadcast ${packet.packetId} for 15s');
    notifyListeners();
    await advertise(packet);
  }
}
