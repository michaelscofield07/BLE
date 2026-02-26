import 'dart:async';
import 'package:flutter/services.dart';
import '../models/tracking_packet.dart';

class IntelligentSosService {
  static const MethodChannel _channel = MethodChannel('intelligent_sos');
  
  // Device context data
  static Map<String, dynamic> _deviceContext = {};
  static final List<Map<String, dynamic>> _ackData = [];
  static Map<String, dynamic> _networkIntelligence = {};

  // Stream controllers for real-time updates
  static final StreamController<Map<String, dynamic>> _deviceContextController = 
      StreamController<Map<String, dynamic>>.broadcast();
  static final StreamController<List<Map<String, dynamic>>> _ackController = 
      StreamController<List<Map<String, dynamic>>>.broadcast();
  static final StreamController<Map<String, dynamic>> _networkController = 
      StreamController<Map<String, dynamic>>.broadcast();

  // Public streams
  static Stream<Map<String, dynamic>> get deviceContextStream => _deviceContextController.stream;
  static Stream<List<Map<String, dynamic>>> get ackDataStream => _ackController.stream;
  static Stream<Map<String, dynamic>> get networkIntelligenceStream => _networkController.stream;

  // Getters for current state
  static Map<String, dynamic> get deviceContext => Map.from(_deviceContext);
  static List<Map<String, dynamic>> get ackData => List.from(_ackData);
  static Map<String, dynamic> get networkIntelligence => Map.from(_networkIntelligence);

  /// Initialize the intelligent SOS service
  static Future<void> initialize() async {
    try {
      await _channel.invokeMethod('initialize');
      
      // Set up method call handler
      _channel.setMethodCallHandler(_handleMethodCall);
      
      // Get initial device context
      await _updateDeviceContext();
      
    } catch (e) {
      print('Error initializing intelligent SOS: $e');
    }
  }

  /// Handle method calls from native Android
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onDeviceContextUpdate':
        final context = Map<String, dynamic>.from(call.arguments);
        _deviceContext = context;
        _deviceContextController.add(_deviceContext);
        break;
        
      case 'onAckReceived':
        final ack = Map<String, dynamic>.from(call.arguments);
        _ackData.add(ack);
        _ackController.add(_ackData);
        break;
        
      case 'onNetworkIntelligenceUpdate':
        final network = Map<String, dynamic>.from(call.arguments);
        _networkIntelligence = network;
        _networkController.add(network);
        break;
        
      default:
        throw PlatformException(code: 'Unimplemented', details: 'Method ${call.method} not implemented');
    }
  }

  /// Update device context from native side
  static Future<void> _updateDeviceContext() async {
    try {
      final context = await _channel.invokeMapMethod('getDeviceContext');
      if (context != null) {
        _deviceContext = Map<String, dynamic>.from(context);
        _deviceContextController.add(_deviceContext);
      }
    } catch (e) {
      print('Error updating device context: $e');
    }
  }

  /// Add acknowledgment data
  static Future<void> addAckData({
    required String ackId,
    required String sosId,
    required int rssi,
    required int timestamp,
  }) async {
    try {
      await _channel.invokeMethod('addAckData', {
        'ackId': ackId,
        'sosId': sosId,
        'rssi': rssi,
        'timestamp': timestamp,
      });
    } catch (e) {
      print('Error adding ACK data: $e');
    }
  }

  /// Get stable nodes for intelligent forwarding
  static Future<List<String>> getStableNodes() async {
    try {
      final result = await _channel.invokeListMethod<String>('getStableNodes');
      return result ?? [];
    } catch (e) {
      print('Error getting stable nodes: $e');
      return [];
    }
  }

  /// Get network stability score
  static Future<double> getNetworkStabilityScore() async {
    try {
      final score = await _channel.invokeMethod<double>('getNetworkStabilityScore');
      return score ?? 0.0;
    } catch (e) {
      print('Error getting network stability score: $e');
      return 0.0;
    }
  }

  /// Get crowd density level
  static Future<String> getCrowdLevel() async {
    try {
      final level = await _channel.invokeMethod<String>('getCrowdLevel');
      return level ?? 'UNKNOWN';
    } catch (e) {
      print('Error getting crowd level: $e');
      return 'UNKNOWN';
    }
  }

  /// Get feature vector for AI/ML processing
  static Future<Map<String, dynamic>?> getFeatureVector() async {
    try {
      final vector = await _channel.invokeMapMethod('getFeatureVector');
      if (vector != null) {
        return Map<String, dynamic>.from(vector);
      }
      return null;
    } catch (e) {
      print('Error getting feature vector: $e');
      return null;
    }
  }

  /// Start continuous monitoring
  static Future<void> startMonitoring() async {
    try {
      await _channel.invokeMethod('startMonitoring');
    } catch (e) {
      print('Error starting monitoring: $e');
    }
  }

  /// Stop continuous monitoring
  static Future<void> stopMonitoring() async {
    try {
      await _channel.invokeMethod('stopMonitoring');
    } catch (e) {
      print('Error stopping monitoring: $e');
    }
  }

  /// Clear ACK data buffer
  static void clearAckData() {
    _ackData.clear();
    _ackController.add(_ackData);
  }

  /// Get intelligent SOS decision based on context
  static Future<Map<String, dynamic>> getSosDecision() async {
    try {
      final decision = await _channel.invokeMapMethod('getSosDecision');
      if (decision != null) {
        return Map<String, dynamic>.from(decision);
      }
      return {
        'shouldForward': true,
        'priority': 'normal',
        'selectedNodes': <String>[],
        'reason': 'Default decision'
      };
    } catch (e) {
      print('Error getting SOS decision: $e');
      return {
        'shouldForward': true,
        'priority': 'normal',
        'selectedNodes': <String>[],
        'reason': 'Fallback decision'
      };
    }
  }

  /// Dispose streams
  static void dispose() {
    _deviceContextController.close();
    _ackController.close();
    _networkController.close();
  }
}
