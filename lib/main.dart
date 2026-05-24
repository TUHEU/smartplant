import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'bluetooth_service.dart';
import 'plant_data.dart';
import 'sensor_database.dart';

// ─────────────────────────────────────────────────────────────
// ENTRY POINT
// ─────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop (Windows / Linux / macOS) needs FFI-based SQLite.
  // Android / iOS use the native sqflite path — no change needed there.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const FarmLinkApp());
}

// ─────────────────────────────────────────────────────────────
// APP ROOT
// ─────────────────────────────────────────────────────────────
class FarmLinkApp extends StatelessWidget {
  const FarmLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FarmLink',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const DashboardScreen(),
    );
  }

  ThemeData _buildTheme() {
    const seed = Color(0xFF3DDC84); // Android green accent
    return ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: seed,
      scaffoldBackgroundColor: const Color(0xFF0D1117),
      fontFamily: 'monospace',
      useMaterial3: true,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// COLOUR PALETTE
// ─────────────────────────────────────────────────────────────
class FLColors {
  static const bg = Color(0xFF0D1117);
  static const surface = Color(0xFF161B22);
  static const card = Color(0xFF1C2333);
  static const border = Color(0xFF30363D);
  static const green = Color(0xFF3DDC84);
  static const cyan = Color(0xFF58D5E8);
  static const amber = Color(0xFFFFB347);
  static const red = Color(0xFFFF5555);
  static const blue = Color(0xFF79B8FF);
  static const purple = Color(0xFFB392F0);
  static const textHi = Color(0xFFE6EDF3);
  static const textMid = Color(0xFF8B949E);
  static const textLow = Color(0xFF484F58);
}

// ─────────────────────────────────────────────────────────────
// DASHBOARD
// ─────────────────────────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  final _bt = BluetoothService();
  final _db = SensorDatabase.instance;

  PlantData _data = PlantData.initial();
  bool _connected = false;
  bool _connecting = false;
  bool _manualOverride = false;
  StreamSubscription<String>? _btSub;

  // Pulse animation for the pump indicator
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Prune old logs on startup
    _db.pruneOldLogs();
    // Start connecting
    _connect();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _btSub?.cancel();
    _bt.dispose();
    super.dispose();
  }

  // ── BLUETOOTH ────────────────────────────────────────────
  Future<void> _connect() async {
    if (_connecting) return;
    setState(() => _connecting = true);
    final ok = await _bt.scanAndConnect();
    if (ok) {
      _btSub = _bt.dataStream.listen(_onData, onError: (_) => _onDisconnect());
    }
    setState(() {
      _connected = ok;
      _connecting = false;
    });
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not find FarmLink_BT. Is HC-05 paired?'),
          backgroundColor: FLColors.red,
        ),
      );
    }
  }

  void _onData(String line) {
    try {
      final parsed = PlantData.fromRawString(line);
      setState(() => _data = parsed);
      _db.insertReading(parsed); // persist to local DB
    } catch (_) {}
  }

  void _onDisconnect() {
    setState(() => _connected = false);
  }

  // ── PUMP CONTROL ─────────────────────────────────────────
  Future<void> _togglePump(bool val) async {
    setState(() => _manualOverride = val);
    await _bt.sendCommand(val ? '1' : '0');
  }

  // ── HELPERS ──────────────────────────────────────────────
  bool get _isTankEmpty => _data.waterLevel <= 10;
  bool get _isPumpActive => (_data.pumpStatus == 1) || _manualOverride;

  String get _systemStatus {
    if (!_connected) return 'DISCONNECTED';
    if (_isTankEmpty) return 'TANK EMPTY';
    if (_isPumpActive) return 'IRRIGATING';
    if (_data.moisture < 30) return 'SOIL DRY';
    return 'OPTIMAL';
  }

  Color get _statusColor {
    if (!_connected) return FLColors.textMid;
    if (_isTankEmpty) return FLColors.red;
    if (_isPumpActive) return FLColors.cyan;
    if (_data.moisture < 30) return FLColors.amber;
    return FLColors.green;
  }

  // ── BUILD ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FLColors.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            _buildAppBar(),
            SliverToBoxAdapter(child: _buildStatusBanner()),
            SliverToBoxAdapter(child: _buildPumpCard()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  'LIVE SENSORS',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 2,
                    color: FLColors.textMid,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.05,
                ),
                delegate: SliverChildListDelegate(_buildSensorCards()),
              ),
            ),
            SliverToBoxAdapter(child: _buildHistoryButton()),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  // ── WIDGETS ───────────────────────────────────────────────

  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      backgroundColor: FLColors.bg,
      pinned: true,
      elevation: 0,
      title: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: FLColors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.eco, color: FLColors.green, size: 16),
          ),
          const SizedBox(width: 10),
          const Text(
            'FARMLINK',
            style: TextStyle(
              color: FLColors.textHi,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
      actions: [
        // Connection button
        GestureDetector(
          onTap: _connecting ? null : (_connected ? null : _connect),
          child: Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: (_connected ? FLColors.green : FLColors.red).withOpacity(
                0.12,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (_connected ? FLColors.green : FLColors.red).withOpacity(
                  0.4,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_connecting)
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: FLColors.amber,
                    ),
                  )
                else
                  Icon(
                    _connected
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth_disabled,
                    size: 12,
                    color: _connected ? FLColors.green : FLColors.red,
                  ),
                const SizedBox(width: 6),
                Text(
                  _connecting
                      ? 'PAIRING…'
                      : (_connected ? 'ONLINE' : 'OFFLINE'),
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w600,
                    color: _connecting
                        ? FLColors.amber
                        : (_connected ? FLColors.green : FLColors.red),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: FLColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _statusColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: _statusColor.withOpacity(0.08),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Opacity(
              opacity: _isPumpActive ? _pulseAnim.value : 1.0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _statusColor,
                  boxShadow: [
                    BoxShadow(
                      color: _statusColor.withOpacity(0.6),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SYSTEM STATUS',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.5,
                    color: FLColors.textMid,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _systemStatus,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _statusColor,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          // Soil moisture quick-read
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'SOIL',
                style: TextStyle(
                  fontSize: 10,
                  color: FLColors.textMid,
                  letterSpacing: 1,
                ),
              ),
              Text(
                '${_data.moisture}%',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: FLColors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPumpCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isPumpActive
              ? [const Color(0xFF0D2137), const Color(0xFF0B3347)]
              : [FLColors.surface, const Color(0xFF1A2030)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isPumpActive
              ? FLColors.cyan.withOpacity(0.4)
              : FLColors.border,
        ),
      ),
      child: Row(
        children: [
          // Icon
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: (_isPumpActive ? FLColors.cyan : FLColors.textLow)
                  .withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.water,
              color: _isPumpActive ? FLColors.cyan : FLColors.textLow,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          // Labels
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WATER PUMP',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 2,
                    color: FLColors.textMid,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isTankEmpty
                      ? 'Tank empty — blocked'
                      : _isPumpActive
                      ? _manualOverride
                            ? 'Manual override ON'
                            : 'Auto-irrigating…'
                      : 'Standby',
                  style: TextStyle(
                    fontSize: 14,
                    color: _isTankEmpty
                        ? FLColors.red
                        : _isPumpActive
                        ? FLColors.cyan
                        : FLColors.textMid,
                  ),
                ),
                // Tank bar
                const SizedBox(height: 8),
                _TankBar(percent: _data.waterLevel),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Switch
          Switch.adaptive(
            value: _manualOverride,
            onChanged: _isTankEmpty ? null : _togglePump,
            activeColor: FLColors.cyan,
            inactiveThumbColor: FLColors.textLow,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSensorCards() {
    return [
      _SensorCard(
        label: 'SOIL MOISTURE',
        value: '${_data.moisture}%',
        icon: Icons.water_drop_outlined,
        accent: FLColors.blue,
        bar: _data.moisture / 100,
        warn: _data.moisture < 30,
      ),
      _SensorCard(
        label: 'TANK LEVEL',
        value: '${_data.waterLevel}%',
        icon: Icons.waves_outlined,
        accent: FLColors.cyan,
        bar: _data.waterLevel / 100,
        warn: _isTankEmpty,
      ),
      _SensorCard(
        label: 'AIR TEMP',
        value: '${_data.airTemp.toStringAsFixed(1)}°C',
        icon: Icons.thermostat_outlined,
        accent: FLColors.amber,
        bar: (_data.airTemp / 50).clamp(0, 1),
        warn: _data.airTemp > 35,
      ),
      _SensorCard(
        label: 'HUMIDITY',
        value: '${_data.airHumid.toStringAsFixed(0)}%',
        icon: Icons.cloud_outlined,
        accent: FLColors.purple,
        bar: _data.airHumid / 100,
      ),
      _SensorCard(
        label: 'SOIL TEMP',
        value: '${_data.soilTemp.toStringAsFixed(1)}°C',
        icon: Icons.grass_outlined,
        accent: FLColors.green,
        bar: (_data.soilTemp / 50).clamp(0, 1),
      ),
      _SensorCard(
        label: 'LIGHT',
        value: '${_data.light}%',
        icon: Icons.wb_sunny_outlined,
        accent: const Color(0xFFFFD700),
        bar: _data.light / 100,
      ),
    ];
  }

  Widget _buildHistoryButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: OutlinedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HistoryScreen()),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: FLColors.border),
          foregroundColor: FLColors.textMid,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.history, size: 18),
        label: const Text(
          'VIEW SENSOR HISTORY',
          style: TextStyle(letterSpacing: 1.5, fontSize: 12),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SENSOR CARD WIDGET
// ─────────────────────────────────────────────────────────────
class _SensorCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final double bar;
  final bool warn;

  const _SensorCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.bar,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayAccent = warn ? FLColors.red : accent;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FLColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: warn ? FLColors.red.withOpacity(0.4) : FLColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: displayAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: displayAccent, size: 20),
          ),
          // Value
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: displayAccent,
              height: 1,
            ),
          ),
          // Label + bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: FLColors.textMid,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: bar.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: displayAccent.withOpacity(0.12),
                  valueColor: AlwaysStoppedAnimation(displayAccent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TANK BAR WIDGET
// ─────────────────────────────────────────────────────────────
class _TankBar extends StatelessWidget {
  final int percent;
  const _TankBar({required this.percent});

  @override
  Widget build(BuildContext context) {
    final color = percent <= 10
        ? FLColors.red
        : percent <= 30
        ? FLColors.amber
        : FLColors.cyan;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (percent / 100).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: color.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$percent%',
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// HISTORY SCREEN
// ─────────────────────────────────────────────────────────────
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _db = SensorDatabase.instance;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await _db.getRecentReadings(limit: 100);
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FLColors.bg,
      appBar: AppBar(
        backgroundColor: FLColors.bg,
        title: const Text(
          'SENSOR HISTORY',
          style: TextStyle(
            color: FLColors.textHi,
            fontSize: 14,
            letterSpacing: 3,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: FLColors.textMid),
        actions: [
          TextButton(
            onPressed: () async {
              await _db.pruneOldLogs(days: 0);
              _load();
            },
            child: const Text(
              'CLEAR',
              style: TextStyle(
                color: FLColors.red,
                fontSize: 11,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: FLColors.green),
            )
          : _rows.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history_outlined,
                    size: 48,
                    color: FLColors.textLow,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No records yet',
                    style: TextStyle(color: FLColors.textMid),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _HistoryRow(row: _rows[i]),
            ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _HistoryRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final ts = DateTime.tryParse(row['timestamp'] ?? '');
    final timeStr = ts != null
        ? '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}'
        : '--:--:--';
    final dateStr = ts != null
        ? '${ts.day.toString().padLeft(2, '0')}/${ts.month.toString().padLeft(2, '0')}'
        : '';

    final pump = (row['pump_status'] as int? ?? 0) == 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: FLColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FLColors.border),
      ),
      child: Row(
        children: [
          // Timestamp
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: FLColors.textHi,
                ),
              ),
              Text(
                dateStr,
                style: const TextStyle(fontSize: 10, color: FLColors.textMid),
              ),
            ],
          ),
          const SizedBox(width: 16),
          const VerticalDivider(color: FLColors.border, width: 1, thickness: 1),
          const SizedBox(width: 16),
          // Metrics chips
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Chip('💧 ${row['moisture']}%', FLColors.blue),
                _Chip(
                  '🌡 ${(row['air_temp'] as double?)?.toStringAsFixed(1) ?? '--'}°',
                  FLColors.amber,
                ),
                _Chip('💦 ${row['water_level']}%', FLColors.cyan),
                _Chip(
                  pump ? '⚡ ON' : '— OFF',
                  pump ? FLColors.cyan : FLColors.textLow,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
