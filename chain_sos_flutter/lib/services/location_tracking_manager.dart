import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/tracking_packet.dart';
import '../services/storage_service.dart';
import 'sos_service.dart';

class LocationTrackingManager extends ChangeNotifier {
  final StorageService storageService;
  final SosService sosService;
  
  Timer? _trackingTimer;
  Timer? _safetyRefreshTimer;
  DateTime? _sosStartTime;
  String? _currentSosId;
  bool _isTracking = false;
  
  Position? _lastValidLocation;
  Position? _lastSentLocation;
  int _stationaryCount = 0;
  DateTime? _lastHeartbeatTime;
  DateTime? _lastSafetyRefreshTime;
  
  static const Duration _maxTrackingDuration = Duration(hours: 1);
  static const double _movementThreshold = 10.0; // meters
  static const int _stationaryThreshold = 3; // consecutive checks
  static const double _gpsAccuracyThreshold = 50.0; // meters
  static const Duration _heartbeatInterval = Duration(minutes: 3);
  static const Duration _safetyRefreshInterval = Duration(minutes: 12);

  LocationTrackingManager({
    required this.storageService,
    required this.sosService,
  });

  bool get isTracking => _isTracking;
  String? get currentSosId => _currentSosId;

  Future<void> startTracking(String sosId) async {
    if (_isTracking) return;
    
    _currentSosId = sosId;
    _sosStartTime = DateTime.now();
    _isTracking = true;
    _stationaryCount = 0;
    _lastHeartbeatTime = null;
    _lastSafetyRefreshTime = null;
    
    // Store SOS start time persistently
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_sos_id', sosId);
    await prefs.setInt('sos_start_time', _sosStartTime!.millisecondsSinceEpoch);
    
    _startTrackingLoop();
    _startSafetyRefreshLoop();
    
    notifyListeners();
  }

  Future<void> stopTracking() async {
    if (!_isTracking) return;
    
    _trackingTimer?.cancel();
    _safetyRefreshTimer?.cancel();
    _isTracking = false;
    _currentSosId = null;
    _sosStartTime = null;
    _lastValidLocation = null;
    _lastSentLocation = null;
    _stationaryCount = 0;
    
    // Clear persisted SOS data
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_sos_id');
    await prefs.remove('sos_start_time');
    
    notifyListeners();
  }

  Future<void> restoreTrackingState() async {
    final prefs = await SharedPreferences.getInstance();
    final sosId = prefs.getString('last_sos_id');
    final sosStartTimeMs = prefs.getInt('sos_start_time');
    
    if (sosId != null && sosStartTimeMs != null) {
      final sosStartTime = DateTime.fromMillisecondsSinceEpoch(sosStartTimeMs);
      final elapsed = DateTime.now().difference(sosStartTime);
      
      if (elapsed < _maxTrackingDuration) {
        _currentSosId = sosId;
        _sosStartTime = sosStartTime;
        _isTracking = true;
        _startTrackingLoop();
        _startSafetyRefreshLoop();
        notifyListeners();
      } else {
        // SOS expired, clean up
        await prefs.remove('last_sos_id');
        await prefs.remove('sos_start_time');
      }
    }
  }

  void _startTrackingLoop() {
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(_getCurrentInterval(), (timer) async {
      if (!_isTracking) {
        timer.cancel();
        return;
      }
      
      // Check if tracking duration exceeded
      if (_sosStartTime != null && 
          DateTime.now().difference(_sosStartTime!) >= _maxTrackingDuration) {
        await stopTracking();
        return;
      }
      
      await _performLocationCheck();
      
      // Update interval for next iteration
      timer.cancel();
      if (_isTracking) {
        _startTrackingLoop();
      }
    });
  }

  void _startSafetyRefreshLoop() {
    _safetyRefreshTimer?.cancel();
    _safetyRefreshTimer = Timer.periodic(_safetyRefreshInterval, (timer) async {
      if (!_isTracking) {
        timer.cancel();
        return;
      }
      
      await _forceSendLocationPacket();
    });
  }

  Duration _getCurrentInterval() {
    if (_sosStartTime == null) return const Duration(minutes: 5);
    
    final elapsed = DateTime.now().difference(_sosStartTime!);
    
    if (elapsed.inMinutes <= 5) {
      return const Duration(seconds: 20);
    } else if (elapsed.inMinutes <= 20) {
      return const Duration(seconds: 50); // Average of 40-60 seconds
    } else if (elapsed.inMinutes <= 60) {
      return const Duration(minutes: 3); // Average of 2-5 minutes
    } else {
      return const Duration(minutes: 10); // Should stop tracking
    }
  }

  Future<void> _performLocationCheck() async {
    try {
      final position = await _getCurrentPosition();
      if (position == null) return;
      
      _lastValidLocation = position;
      
      // Check if user is stationary
      final isStationary = _isUserStationary(position);
      
      if (isStationary) {
        _stationaryCount++;
        
        // Send heartbeat if stationary for threshold duration
        if (_shouldSendHeartbeat()) {
          await _sendHeartbeatPacket();
        }
      } else {
        // User moved, send location packet immediately
        _stationaryCount = 0;
        await _sendLocationPacket(position, LocationConfidence.HIGH);
      }
      
    } catch (e) {
      debugPrint('Location check failed: $e');
    }
  }

  Future<void> _forceSendLocationPacket() async {
    if (_lastValidLocation != null) {
      await _sendLocationPacket(_lastValidLocation!, LocationConfidence.HIGH);
    }
  }

  Future<Position?> _getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;
      
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      // Validate GPS reliability
      if (!_isGpsReliable(position)) {
        // Fall back to last known valid location
        return _lastValidLocation;
      }
      
      return position;
      
    } catch (e) {
      debugPrint('Error getting position: $e');
      return _lastValidLocation;
    }
  }

  bool _isGpsReliable(Position position) {
    // Check accuracy
    if (position.accuracy > _gpsAccuracyThreshold) {
      return false;
    }
    
    // Check timestamp (not too old)
    final age = DateTime.now().difference(position.timestamp);
    if (age.inSeconds > 30) {
      return false;
    }
    
    // Check for unrealistic speed jumps if we have previous location
    if (_lastValidLocation != null) {
      final distance = Geolocator.distanceBetween(
        _lastValidLocation!.latitude,
        _lastValidLocation!.longitude,
        position.latitude,
        position.longitude,
      );
      
      final timeDiff = position.timestamp.difference(_lastValidLocation!.timestamp);
      if (timeDiff.inSeconds > 0) {
        final speed = distance / timeDiff.inSeconds; // m/s
        if (speed > 100) { // > 360 km/h is unrealistic
          return false;
        }
      }
    }
    
    return true;
  }

  bool _isUserStationary(Position currentPosition) {
    if (_lastSentLocation == null) return false;
    
    final distance = Geolocator.distanceBetween(
      _lastSentLocation!.latitude,
      _lastSentLocation!.longitude,
      currentPosition.latitude,
      currentPosition.longitude,
    );
    
    return distance < _movementThreshold;
  }

  bool _shouldSendHeartbeat() {
    if (_lastHeartbeatTime == null) return true;
    
    final timeSinceLastHeartbeat = DateTime.now().difference(_lastHeartbeatTime!);
    return timeSinceLastHeartbeat >= _heartbeatInterval;
  }

  Future<void> _sendLocationPacket(Position position, LocationConfidence confidence) async {
    if (_currentSosId == null) return;
    
    final deviceId = await storageService.getDeviceId();
    final packet = TrackingPacket.createTrackPacket(
      deviceId: deviceId,
      sosId: _currentSosId!,
      lat: position.latitude,
      lon: position.longitude,
      confidence: confidence,
    );
    
    await _sendPacket(packet);
    _lastSentLocation = position;
  }

  Future<void> _sendHeartbeatPacket() async {
    if (_currentSosId == null) return;
    
    final deviceId = await storageService.getDeviceId();
    final packet = TrackingPacket.createHeartbeatPacket(
      deviceId: deviceId,
      sosId: _currentSosId!,
    );
    
    await _sendPacket(packet);
    _lastHeartbeatTime = DateTime.now();
  }

  Future<void> _sendPacket(TrackingPacket packet) async {
    try {
      // Try to send online first
      final online = await _hasInternet();
      if (online) {
        await _sendPacketOnline(packet);
      } else {
        // Store for offline forwarding via BLE
        await _storePacketOffline(packet);
      }
    } catch (e) {
      debugPrint('Failed to send tracking packet: $e');
      await _storePacketOffline(packet);
    }
  }

  Future<bool> _hasInternet() async {
    if (sosService.forceOnline) return true;
    final connectivity = await Connectivity().checkConnectivity();
    return connectivity.contains(ConnectivityResult.mobile) ||
        connectivity.contains(ConnectivityResult.wifi) ||
        connectivity.contains(ConnectivityResult.ethernet);
  }

  Future<void> _sendPacketOnline(TrackingPacket packet) async {
    // This would be implemented to send to your tracking endpoint
    // For now, we'll use the existing SOS service infrastructure
    final url = Uri.parse('${sosService.backendBaseUrl}/tracking');
    
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(packet.toJson()),
      );
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        sosService.logs.add('Tracking packet sent: ${packet.packetId}');
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to send tracking packet: $e');
    }
    
    sosService.notifyListeners();
  }

  Future<void> _storePacketOffline(TrackingPacket packet) async {
    // Store packet for offline forwarding via BLE
    // This would integrate with your existing BLE service
    await storageService.storeTrackingPacket(packet);
    sosService.logs.add('Tracking packet stored offline: ${packet.packetId}');
    sosService.notifyListeners();
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _safetyRefreshTimer?.cancel();
    super.dispose();
  }
}
