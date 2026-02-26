import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/tracking_packet.dart';

class StorageService extends ChangeNotifier {
  late final SharedPreferences _prefs;
  Database? _db;

  static const _deviceIdKey = 'device_id';
  static const _nameKey = 'user_name';
  static const _contactsKey = 'emergency_contacts';
  static const _lastLatKey = 'last_lat';
  static const _lastLonKey = 'last_lon';
  static const _lastTsKey = 'last_ts';

  StorageService._();

  static Future<StorageService> create() async {
    final s = StorageService._();
    s._prefs = await SharedPreferences.getInstance();
    await s._openDb();
    // seed device id if missing
    if (!(s._prefs.containsKey(_deviceIdKey))) {
      final rnd = DateTime.now().millisecondsSinceEpoch;
      await s._prefs.setString(_deviceIdKey, 'device-$rnd');
    }
    return s;
  }

  Future<void> _openDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'chainsos.db');
    _db = await openDatabase(path, version: 2, onCreate: (db, v) async {
      await db.execute(
          'CREATE TABLE IF NOT EXISTS seen_packets (packet_id TEXT PRIMARY KEY, expires_at_ms INTEGER)');
      await db.execute(
          'CREATE TABLE IF NOT EXISTS tracking_packets (id INTEGER PRIMARY KEY AUTOINCREMENT, packet_data TEXT, created_at_ms INTEGER)');
    }, onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await db.execute(
            'CREATE TABLE IF NOT EXISTS tracking_packets (id INTEGER PRIMARY KEY AUTOINCREMENT, packet_data TEXT, created_at_ms INTEGER)');
      }
    });
  }

  Future<String> getDeviceId() async =>
      _prefs.getString(_deviceIdKey) ?? 'unknown-device';
  Future<void> setDeviceId(String value) async {
    await _prefs.setString(_deviceIdKey, value);
    notifyListeners();
  }

  String get name => _prefs.getString(_nameKey) ?? '';
  Future<void> setName(String value) async {
    await _prefs.setString(_nameKey, value);
    notifyListeners();
  }

  String get contactsCsv => _prefs.getString(_contactsKey) ?? '';
  Future<void> setContactsCsv(String value) async {
    await _prefs.setString(_contactsKey, value);
    notifyListeners();
  }

  Future<void> setLastLocation(double lat, double lon, int ts) async {
    await _prefs.setDouble(_lastLatKey, lat);
    await _prefs.setDouble(_lastLonKey, lon);
    await _prefs.setInt(_lastTsKey, ts);
    notifyListeners();
  }

  double? get lastLat => _prefs.getDouble(_lastLatKey);
  double? get lastLon => _prefs.getDouble(_lastLonKey);
  int? get lastTs => _prefs.getInt(_lastTsKey);

  Future<bool> hasSeenPacket(String packetId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await _db!.query('seen_packets',
        where: 'packet_id = ? AND expires_at_ms > ?',
        whereArgs: [packetId, now],
        limit: 1);
    return rows.isNotEmpty;
  }

  Future<void> rememberPacket(String packetId,
      {required int ttlMinutes}) async {
    final expires = DateTime.now()
        .add(Duration(minutes: ttlMinutes))
        .millisecondsSinceEpoch;
    await _db!.insert(
        'seen_packets', {'packet_id': packetId, 'expires_at_ms': expires},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> storeTrackingPacket(TrackingPacket packet) async {
    final packetJson = jsonEncode(packet.toJson());
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db!.insert(
        'tracking_packets', 
        {'packet_data': packetJson, 'created_at_ms': now},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<TrackingPacket>> getStoredTrackingPackets() async {
    final rows = await _db!.query('tracking_packets', 
        orderBy: 'created_at_ms DESC',
        limit: 100); // Limit to prevent memory issues
    
    return rows.map((row) {
      final packetJson = row['packet_data'] as String;
      final packetMap = jsonDecode(packetJson) as Map<String, dynamic>;
      return TrackingPacket.fromJson(packetMap);
    }).toList();
  }

  Future<void> clearStoredTrackingPackets() async {
    await _db!.delete('tracking_packets');
  }

  Future<void> cleanupOldTrackingPackets({int hoursOld = 24}) async {
    final cutoffTime = DateTime.now()
        .subtract(Duration(hours: hoursOld))
        .millisecondsSinceEpoch;
    
    await _db!.delete('tracking_packets',
        where: 'created_at_ms < ?',
        whereArgs: [cutoffTime]);
  }
}
