import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../services/storage_service.dart';

class SosPacket {
  final String packetId;
  final String deviceId;
  final int roundedTs; // seconds rounded to 30s
  final double lat;
  final double lon;
  final String message;

  SosPacket({
    required this.packetId,
    required this.deviceId,
    required this.roundedTs,
    required this.lat,
    required this.lon,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
        'packet_id': packetId,
        'device_id': deviceId,
        'timestamp': roundedTs,
        'lat': lat,
        'lon': lon,
        'message': message,
      };

  static SosPacket fromJson(Map<String, dynamic> json) => SosPacket(
        packetId: json['packet_id'] as String,
        deviceId: json['device_id'] as String,
        roundedTs: (json['timestamp'] as num).toInt(),
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        message: json['message'] as String,
      );
}

class SosService extends ChangeNotifier {
  final StorageService storageService;
  bool forceOnline = false; // testing toggle
  String backendBaseUrl = 'http://192.168.43.47:5000';
  final List<String> logs = <String>[];

  SosService({required this.storageService});
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
        logs.add('Forward attempt $attempt (${online ? "Device is Online" : "Device is Offline"}) for ${packet.packetId}');
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
      logs.add('Generated packet ${packet.packetId}. ${online ? "Device is Online" : "Device is Offline"}');
      notifyListeners();
      if (online) {
        await sendPacketOnline(packet);
      } else {
        if (onOffline != null) {
          await onOffline(packet);
        }
      }
      return true;
    } catch (e) {
      logs.add('Error: $e');
      notifyListeners();
      return false;
    }
  }
}
