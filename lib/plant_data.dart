import 'package:flutter/foundation.dart';

/// Matches Arduino CSV exactly:
/// moisturePercent,waterPercent,airTemp,airHumid,soilTemperature,lightPercent,motionDetected,pumpOn
class PlantData {
  final int moisture; // 0-100%
  final int waterLevel; // 0-100%
  final double airTemp; // °C
  final double airHumid; // 0-100%
  final double soilTemp; // °C
  final int light; // 0-100%
  final int motion; // 0 or 1
  final int pumpStatus; // 0 or 1

  const PlantData({
    required this.moisture,
    required this.waterLevel,
    required this.airTemp,
    required this.airHumid,
    required this.soilTemp,
    required this.light,
    required this.motion,
    required this.pumpStatus,
  });

  factory PlantData.fromRawString(String raw) {
    final clean = raw.replaceAll('\r', '').trim();
    final parts = clean.split(',');

    if (kDebugMode) print('[Data] Parsing "$clean" → ${parts.length} fields');

    if (parts.length != 8) {
      throw FormatException('Expected 8 fields, got ${parts.length}: "$clean"');
    }

    return PlantData(
      moisture: _i(parts[0], 'moisture'),
      waterLevel: _i(parts[1], 'waterLevel'),
      airTemp: _d(parts[2], 'airTemp'),
      airHumid: _d(parts[3], 'airHumid'),
      soilTemp: _d(parts[4], 'soilTemp'),
      light: _i(parts[5], 'light'),
      motion: _i(parts[6], 'motion'),
      pumpStatus: _i(parts[7], 'pumpStatus'),
    );
  }

  static int _i(String s, String f) {
    final v = int.tryParse(s.trim());
    if (v == null) throw FormatException('Bad int "$s" for $f');
    return v;
  }

  static double _d(String s, String f) {
    final v = double.tryParse(s.trim());
    if (v == null) throw FormatException('Bad double "$s" for $f');
    return v;
  }

  factory PlantData.initial() => const PlantData(
    moisture: 0,
    waterLevel: 0,
    airTemp: 0,
    airHumid: 0,
    soilTemp: 0,
    light: 0,
    motion: 0,
    pumpStatus: 0,
  );

  @override
  String toString() =>
      'PlantData(moist=$moisture water=$waterLevel '
      'airT=$airTemp humid=$airHumid soilT=$soilTemp '
      'light=$light motion=$motion pump=$pumpStatus)';
}
