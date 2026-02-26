import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'storage_service.dart';
import 'sos_service.dart';

class Acknowledgment {
  final String senderId;
  final DateTime timestamp;
  final int rssi;
  final String sosId;
  final String ackId;

  Acknowledgment({
    required this.senderId,
    required this.timestamp,
    required this.rssi,
    required this.sosId,
    required this.ackId,
  });

  @override
  String toString() {
    return 'Acknowledgment from $senderId (RSSI: $rssi, SOS: $sosId)';
  }
}

class BleService extends ChangeNotifier {
  final StorageService storageService;
  final SosService sosService;
  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();

  final List<String> logs = <String>[];
  final Map<String, Acknowledgment> _acknowledgments = {};
  bool scanning = false;
  bool advertising = false;

  // Getters
  List<Acknowledgment> get acknowledgments => _acknowledgments.values.toList();
  int get nearbyDevicesCount => _acknowledgments.length;

  BleService({required this.storageService, required this.sosService});
  static const int _manufacturerId = 0x1337;

  // Encode acknowledgment packet with all details
  List<int> _encodeAckPayload({
    required String targetDeviceId,
    required String senderId,
    required int rssi,
    required String sosId,
    required String ackId,
  }) {
    // Convert strings to bytes
    final senderIdBytes = utf8.encode(senderId);
    final targetIdBytes = utf8.encode(targetDeviceId);
    final sosIdBytes = utf8.encode(sosId);
    final ackIdBytes = utf8.encode(ackId);
    
    // Calculate lengths (clamp to fit in 1 byte each)
    final targetIdLen = targetIdBytes.length.clamp(0, 255);
    final senderIdLen = senderIdBytes.length.clamp(0, 255);
    final sosIdLen = sosIdBytes.length.clamp(0, 255);
    final ackIdLen = ackIdBytes.length.clamp(0, 255);
    
    // Get current timestamp (4 bytes)
    final now = DateTime.now();
    final timestamp = now.millisecondsSinceEpoch ~/ 1000; // Convert to seconds
    
    // Convert RSSI to 1 byte (signed byte, -128 to 127)
    final rssiByte = rssi.clamp(-128, 127);
    
    return <int>[
      0x04, // Version 4 for acknowledgment
      // Timestamp (4 bytes)
      (timestamp >> 24) & 0xFF,
      (timestamp >> 16) & 0xFF,
      (timestamp >> 8) & 0xFF,
      timestamp & 0xFF,
      // RSSI (1 byte)
      rssiByte,
      // Lengths (1 byte each)
      targetIdLen,
      senderIdLen,
      sosIdLen,
      ackIdLen,
      // Data
      ...targetIdBytes,
      ...senderIdBytes,
      ...sosIdBytes,
      ...ackIdBytes,
    ];
  }

  // Decode acknowledgment packet
  ({
    String targetId,
    String senderId,
    String sosId,
    String ackId,
    DateTime timestamp,
    int rssi,
  })? _decodeAckPayload(List<int> bytes) {
    if (bytes.length < 9) return null; // Minimum length check
    
    try {
      int pos = 1; // Skip version byte
      
      // Read timestamp (4 bytes)
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        ((bytes[pos] << 24) | 
         (bytes[pos+1] << 16) | 
         (bytes[pos+2] << 8) | 
         bytes[pos+3]) * 1000,
        isUtc: true,
      );
      pos += 4;
      
      // Read RSSI (1 byte, signed)
      final rssi = bytes[pos] > 127 ? bytes[pos] - 256 : bytes[pos];
      pos += 1;
      
      // Read lengths (1 byte each)
      final targetIdLen = bytes[pos++];
      final senderIdLen = bytes[pos++];
      final sosIdLen = bytes[pos++];
      final ackIdLen = bytes[pos++];
      
      // Validate lengths
      if (bytes.length < pos + targetIdLen + senderIdLen + sosIdLen + ackIdLen) {
        return null;
      }
      
      // Read data
      final targetId = utf8.decode(bytes.sublist(pos, pos + targetIdLen));
      pos += targetIdLen;
      
      final senderId = utf8.decode(bytes.sublist(pos, pos + senderIdLen));
      pos += senderIdLen;
      
      final sosId = utf8.decode(bytes.sublist(pos, pos + sosIdLen));
      pos += sosIdLen;
      
      final ackId = utf8.decode(bytes.sublist(pos, pos + ackIdLen));
      
      return (
        targetId: targetId,
        senderId: senderId,
        sosId: sosId,
        ackId: ackId,
        timestamp: timestamp,
        rssi: rssi,
      );
    } catch (e) {
      logs.add('Error decoding ACK: $e');
      return null;
    }
  }

  // Send acknowledgment for a received packet
  Future<void> sendAcknowledgment({
    required String targetDeviceId,
    required String sosId,
    required int rssi,
  }) async {
    try {
      final deviceId = await storageService.getDeviceId();
      final ackId = 'ack-${DateTime.now().millisecondsSinceEpoch}';
      
      final ackPayload = _encodeAckPayload(
        targetDeviceId: targetDeviceId,
        senderId: deviceId,
        rssi: rssi,
        sosId: sosId,
        ackId: ackId,
      );
      
      logs.add('Sending ACK to $targetDeviceId for SOS $sosId (RSSI: $rssi)');
      notifyListeners();
      
      await _blePeripheral.start(
        advertiseData: AdvertiseData(
          includeDeviceName: false,
          manufacturerId: _manufacturerId,
          manufacturerData: Uint8List.fromList(ackPayload),
        ),
        advertiseSettings: AdvertiseSettings(
          advertiseMode: AdvertiseMode.advertiseModeLowLatency,
          txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
          connectable: false,
          timeout: 0,
        ),
      );
      
      await Future.delayed(const Duration(seconds: 2));
      await _blePeripheral.stop();
    } catch (e) {
      logs.add('Failed to send ACK: $e');
      notifyListeners();
    }
  }

  // Decode SOS packet
  ({
    int ts30,
    double lat,
    double lon,
    String senderId,
    int hopCount,
    int maxHops,
  })? _decodePayload(List<int> bytes) {
    if (bytes.isEmpty) return null;
    final ver = bytes[0];
    
    if (ver == 0x03) {
      if (bytes.length < 14) return null;
      
      // Read timestamp (4 bytes)
      final int ts30 = (bytes[1] << 24) | (bytes[2] << 16) | (bytes[3] << 8) | bytes[4];
      
      // Read latitude (3 bytes)
      final int latI = (bytes[5] << 16) | (bytes[6] << 8) | bytes[7];
      
      // Read longitude (3 bytes)
      final int lonI = (bytes[8] << 16) | (bytes[9] << 8) | bytes[10];
      
      // Read hop count and max hops
      final int hopCount = bytes[11];
      final int maxHops = bytes[12];
      
      // Read sender ID
      final int idLen = bytes[13];
      if (bytes.length < 14 + idLen) return null;
      
      final idBytes = bytes.sublist(14, 14 + idLen);
      final senderId = utf8.decode(idBytes);
      
      // Convert coordinates back to double
      final double lat = (latI / 10000.0) - 90.0;
      final double lon = (lonI / 10000.0) - 180.0;
      
      return (
        ts30: ts30,
        lat: lat,
        lon: lon,
        senderId: senderId,
        hopCount: hopCount,
        maxHops: maxHops,
      );
    } else {
      logs.add('Unsupported packet version: 0x${ver.toRadixString(16)}');
      return null;
    }
  }

  List<int> _encodePayload(SosPacket p, String deviceId) {
    final int ts30 = (p.roundedTs ~/ 30).clamp(0, 0xFFFFFFFF);
    final int latI = ((p.lat + 90.0) * 10000).round().clamp(0, 0xFFFFFF);
    final int lonI = ((p.lon + 180.0) * 10000).round().clamp(0, 0xFFFFFF);
    final idBytesFull = utf8.encode(deviceId);
    final List<int> idBytes = idBytesFull.length > 11
        ? idBytesFull.sublist(0, 11)
        : idBytesFull;
    final idLen = idBytes.length.clamp(0, 255);
    return <int>[
      0x03, 
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
      p.hopCount.clamp(0, 255),  
      p.maxHops.clamp(0, 255),    
      idLen,
      ...idBytes,
    ];
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
        try {
          final data = r.advertisementData.manufacturerData[_manufacturerId];
          if (data == null || data.isEmpty) continue;

          // Handle acknowledgment packets
          if (data.isNotEmpty && data[0] == 0x04) {
            final ack = _decodeAckPayload(data);
            if (ack != null) {
              final deviceId = await storageService.getDeviceId();
              
              if (ack.targetId == deviceId) {
                // Store acknowledgment with all details
                _acknowledgments[ack.senderId] = Acknowledgment(
                  senderId: ack.senderId,
                  timestamp: ack.timestamp,
                  rssi: ack.rssi,
                  sosId: ack.sosId,
                  ackId: ack.ackId,
                );
                
                // Log the acknowledgment
                logs.add('''
Received ACK from ${ack.senderId}
  - SOS ID: ${ack.sosId}
  - ACK ID: ${ack.ackId}
  - RSSI: ${ack.rssi} dBm
  - Time: ${ack.timestamp.toString()}
''');
                
                // Clean up old acknowledgments (older than 5 minutes)
                final now = DateTime.now();
                _acknowledgments.removeWhere((_, ack) => 
                  now.difference(ack.timestamp) > const Duration(minutes: 5));
                
                notifyListeners();
              }
            }
            continue;
          }

          // Process regular SOS packet
          final decoded = _decodePayload(data);
          if (decoded == null) continue;

          // Check hop count
          if (decoded.hopCount >= decoded.maxHops) {
            logs.add('Dropping packet from ${decoded.senderId}: max hops (${decoded.maxHops}) reached');
            notifyListeners();
            continue;
          }

          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final roundedNow = (now ~/ 30) * 30;
          final originalTimestamp = decoded.ts30 * 30;  // Convert back to seconds
          final packetId = '${decoded.senderId}-$originalTimestamp';

          // Check if we've seen this packet recently
          final seen = await storageService.hasSeenPacket(packetId);
          if (seen) {
            continue; // Already processed this packet
          }
          await storageService.rememberPacket(packetId, ttlMinutes: 10);

          // Create a new packet with the received data and incremented hop count
          final packet = SosPacket(
            packetId: packetId,
            deviceId: decoded.senderId,
            roundedTs: decoded.ts30 * 30, // Convert back to seconds
            lat: decoded.lat,
            lon: decoded.lon,
            message: 'SOS',
            hopCount: decoded.hopCount + 1, // Increment hop count
            maxHops: decoded.maxHops,
          );

          logs.add('Received packet from ${decoded.senderId} (hops: ${decoded.hopCount}/${decoded.maxHops})');
          notifyListeners();

          // If we're the first hop, send acknowledgment
          if (decoded.hopCount == 0) {
            await sendAcknowledgment(
              targetDeviceId: decoded.senderId,
              sosId: packet.packetId,
              rssi: r.rssi,
            );
          }
          
          // Forward the packet
          await sosService.sendPacketOnlineWithRetry(packet);
          
          // Only re-broadcast if we haven't reached max hops
          if (packet.hopCount < packet.maxHops && Platform.isAndroid) {
            logs.add('Forwarding packet (new hop count: ${packet.hopCount})');
            notifyListeners();
            await advertise(packet);
          } else {
            logs.add('Not forwarding: max hops reached');
            notifyListeners();
          }
        } catch (e) {
          logs.add('Error processing BLE packet: $e');
          notifyListeners();
          if (kDebugMode) {
            print('Error processing BLE packet: $e');
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
