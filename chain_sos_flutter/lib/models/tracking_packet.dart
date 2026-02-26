enum TrackingPacketType {
  TRACK_PACKET,
  HEARTBEAT_PACKET,
}

enum LocationConfidence {
  HIGH,
  LOW_CONFIDENCE,
}

class TrackingPacket {
  final String packetId;
  final String deviceId;
  final String sosId;
  final int timestamp;
  final TrackingPacketType type;
  final double? lat;
  final double? lon;
  final LocationConfidence confidence;
  final int packetSize;

  TrackingPacket({
    required this.packetId,
    required this.deviceId,
    required this.sosId,
    required this.timestamp,
    required this.type,
    this.lat,
    this.lon,
    this.confidence = LocationConfidence.HIGH,
  }) : packetSize = _calculatePacketSize();

  static int _calculatePacketSize() {
    return 255; // Max packet size constraint
  }

  Map<String, dynamic> toJson() => {
        'packet_id': packetId,
        'device_id': deviceId,
        'sos_id': sosId,
        'timestamp': timestamp,
        'type': type.name,
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
        'confidence': confidence.name,
      };

  factory TrackingPacket.fromJson(Map<String, dynamic> json) => TrackingPacket(
        packetId: json['packet_id'],
        deviceId: json['device_id'],
        sosId: json['sos_id'],
        timestamp: json['timestamp'],
        type: TrackingPacketType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => TrackingPacketType.TRACK_PACKET,
        ),
        lat: json['lat']?.toDouble(),
        lon: json['lon']?.toDouble(),
        confidence: LocationConfidence.values.firstWhere(
          (e) => e.name == json['confidence'],
          orElse: () => LocationConfidence.HIGH,
        ),
      );

  factory TrackingPacket.createTrackPacket({
    required String deviceId,
    required String sosId,
    required double lat,
    required double lon,
    required LocationConfidence confidence,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return TrackingPacket(
      packetId: '$deviceId-track-$now',
      deviceId: deviceId,
      sosId: sosId,
      timestamp: now,
      type: TrackingPacketType.TRACK_PACKET,
      lat: lat,
      lon: lon,
      confidence: confidence,
    );
  }

  factory TrackingPacket.createHeartbeatPacket({
    required String deviceId,
    required String sosId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return TrackingPacket(
      packetId: '$deviceId-hb-$now',
      deviceId: deviceId,
      sosId: sosId,
      timestamp: now,
      type: TrackingPacketType.HEARTBEAT_PACKET,
    );
  }
}
