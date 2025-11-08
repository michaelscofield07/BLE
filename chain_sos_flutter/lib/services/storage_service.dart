import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class StorageService extends ChangeNotifier {
  late final SharedPreferences _prefs;
  Database? _db;

  static const _deviceIdKey = 'device_id';
  static const _nameKey = 'user_name';
  static const _contactsKey = 'emergency_contacts'; // comma-separated
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
    _db = await openDatabase(path, version: 1, onCreate: (db, v) async {
      await db.execute(
          'CREATE TABLE IF NOT EXISTS seen_packets (packet_id TEXT PRIMARY KEY, expires_at_ms INTEGER)');
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
}
