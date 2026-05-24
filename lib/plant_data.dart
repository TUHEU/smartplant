/// PlantData — typed model for one sensor reading.
///
/// CSV format from Arduino (8 fields):
/// Moisture,WaterLevel,AirTemp,AirHumid,SoilTemp,Light,Motion,PumpStatus
class PlantData {
  final int moisture; // 0–100 %
  final int waterLevel; // 0–100 %
  final double airTemp; // °C
  final double airHumid; // 0–100 %
  final double soilTemp; // °C
  final int light; // 0–100 %
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

  /// Parse the Arduino CSV string.
  factory PlantData.fromRawString(String raw) {
    final parts = raw.trim().split(',');
    if (parts.length != 8) {
      throw FormatException('Expected 8 fields, got ${parts.length}: "$raw"');
    }
    return PlantData(
      moisture: int.parse(parts[0]),
      waterLevel: int.parse(parts[1]),
      airTemp: double.parse(parts[2]),
      airHumid: double.parse(parts[3]),
      soilTemp: double.parse(parts[4]),
      light: int.parse(parts[5]),
      motion: int.parse(parts[6]),
      pumpStatus: int.parse(parts[7]),
    );
  }

  /// Dummy / initial state so the UI has something to show before first packet.
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

  PlantData copyWith({
    int? moisture,
    int? waterLevel,
    double? airTemp,
    double? airHumid,
    double? soilTemp,
    int? light,
    int? motion,
    int? pumpStatus,
  }) => PlantData(
    moisture: moisture ?? this.moisture,
    waterLevel: waterLevel ?? this.waterLevel,
    airTemp: airTemp ?? this.airTemp,
    airHumid: airHumid ?? this.airHumid,
    soilTemp: soilTemp ?? this.soilTemp,
    light: light ?? this.light,
    motion: motion ?? this.motion,
    pumpStatus: pumpStatus ?? this.pumpStatus,
  );
}
