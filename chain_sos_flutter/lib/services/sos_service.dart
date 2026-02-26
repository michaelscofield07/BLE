import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../services/storage_service.dart';
import '../services/location_tracking_manager.dart';
import '../services/intelligent_sos_service.dart';

class SosPacket {
  final String packetId;
  final String deviceId;
  final int roundedTs;
  final double lat;
  final double lon;
  final String message;
  final int hopCount;
  final int maxHops;

  SosPacket({
    required this.packetId,
    required this.deviceId,
    required this.roundedTs,
    required this.lat,
    required this.lon,
    required this.message,
    this.hopCount = 0,
    this.maxHops = 13,
  });

  SosPacket copyWith({
    String? packetId,
    String? deviceId,
    int? roundedTs,
    double? lat,
    double? lon,
    String? message,
    int? hopCount,
    int? maxHops,
  }) {
    return SosPacket(
      packetId: packetId ?? this.packetId,
      deviceId: deviceId ?? this.deviceId,
      roundedTs: roundedTs ?? this.roundedTs,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      message: message ?? this.message,
      hopCount: hopCount ?? this.hopCount,
      maxHops: maxHops ?? this.maxHops,
    );
  }

  Map<String, dynamic> toJson() => {
        'packet_id': packetId,
        'device_id': deviceId,
        'timestamp': roundedTs,
        'lat': lat,
        'lon': lon,
        'message': message,
        'hop_count': hopCount,
        'max_hops': maxHops,
      };

  factory SosPacket.fromJson(Map<String, dynamic> json) => SosPacket(
        packetId: json['packet_id'],
        deviceId: json['device_id'],
        roundedTs: json['timestamp'],
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        message: json['message'],
        hopCount: json['hop_count'] ?? 0,
        maxHops: json['max_hops'] ?? 13,
      );
}

class SosService extends ChangeNotifier {
  final StorageService storageService;
  LocationTrackingManager? _trackingManager;
  bool forceOnline = false;
  String backendBaseUrl = 'http://10.67.183.231:5000';
  final List<String> logs = <String>[];

  SosService({required this.storageService});

  LocationTrackingManager get trackingManager {
    _trackingManager ??= LocationTrackingManager(
      storageService: storageService,
      sosService: this,
    );
    return _trackingManager!;
  }
  void setForceOnline(bool value) {
    forceOnline = value;
    notifyListeners();
  }

  Future<bool> _hasInternet() async {
    if (forceOnline) return true;
    final result = await Connectivity().checkConnectivity();
    return result.contains(ConnectivityResult.mobile) ||
        result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.ethernet);
  }

  Future<Position> _getPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied');
    }
    return Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }

  int _roundTo30s(int epochSeconds) {
    return (epochSeconds ~/ 30) * 30;
  }

  Future<SosPacket> createPacket({String? message}) async {
    final pos = await _getPosition();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rounded = _roundTo30s(now);
    final deviceId = await storageService.getDeviceId();
    final packetId = '$deviceId-$rounded';
    final packet = SosPacket(
      packetId: packetId,
      deviceId: deviceId,
      roundedTs: rounded,
      lat: pos.latitude,
      lon: pos.longitude,
      message: message ?? 'SOS',
    );
    await storageService.setLastLocation(pos.latitude, pos.longitude, rounded);
    return packet;
  }

  Future<void> sendPacketOnline(SosPacket packet) async {
    final url = Uri.parse('$backendBaseUrl/receive');
    try {
      final res = await http.post(url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(packet.toJson()));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        logs.add('HTTP request sent');
      } else {
        logs.add('HTTP request failed (status ${res.statusCode})');
      }
    } catch (e) {
      logs.add('HTTP request failed');
    }
    notifyListeners();
  }

  Future<void> sendPacketOnlineWithRetry(SosPacket packet,
      {int maxAttempts = 5}) async {
    int attempt = 0;
    int delayMs = 1000;
    while (true) {
      attempt += 1;
      try {
        final online = await _hasInternet();
        logs.add(
            'Forward attempt $attempt (${online ? "Device is Online" : "Device is Offline"}) for ${packet.packetId}');
        notifyListeners();
        await sendPacketOnline(packet);
        return;
      } catch (e) {
        logs.add('Forward failed (attempt $attempt): $e');
        notifyListeners();
        if (attempt >= maxAttempts) rethrow;
        await Future.delayed(Duration(milliseconds: delayMs));
        delayMs = (delayMs * 2).clamp(1000, 30000);
      }
    }
  }

  Future<bool> sendSOS(
      {String? message, Future<void> Function(SosPacket)? onOffline}) async {
    try {
      final packet = await createPacket(message: message);
      final online = await _hasInternet();
      logs.add(
          'Generated packet ${packet.packetId}. ${online ? "Device is Online" : "Device is Offline"}');
      notifyListeners();
      
      // Get intelligent SOS decision
      final decision = await IntelligentSosService.getSosDecision();
      logs.add('Intelligent decision: ${decision['reason']}');
      
      // Start live location tracking
      await trackingManager.startTracking(packet.packetId);
      logs.add('Started live location tracking for ${packet.packetId}');
      
      if (online) {
        await sendPacketOnline(packet);
      } else {
        // Use intelligent forwarding for offline
        if (decision['shouldForward'] == true) {
          if (onOffline != null) {
            await onOffline(packet);
          }
          logs.add('Intelligent forwarding: Priority ${decision['priority']}');
        } else {
          logs.add('SOS forwarding disabled: ${decision['reason']}');
        }
      }
      return true;
    } catch (e) {
      logs.add('Error: $e');
      notifyListeners();
      return false;
    }
  }

  Future<void> stopLiveTracking() async {
    await trackingManager.stopTracking();
    logs.add('Stopped live location tracking');
    notifyListeners();
  }

  Future<void> initializeTracking() async {
    await trackingManager.restoreTrackingState();
    // Initialize intelligent SOS
    await IntelligentSosService.initialize();
    await IntelligentSosService.startMonitoring();
  }
}
