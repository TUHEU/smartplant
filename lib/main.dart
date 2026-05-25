import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'bluetooth_service.dart';
import 'plant_data.dart';
import 'sensor_database.dart';

// ══════════════════════════════════════════════════════════════
//  ARDUINO THRESHOLDS — must match your Arduino code exactly
// ══════════════════════════════════════════════════════════════
const int kSoilMoistureLow = 40; // % — below this = soil dry
const double kSoilTempHigh = 30.0; // °C — above this = soil too hot
const double kAirTempHot = 32.0; // °C — above this = air too hot
const int kWaterLowThresh = 15; // % — below/equal = tank empty

// ══════════════════════════════════════════════════════════════
//  ENTRY POINT
// ══════════════════════════════════════════════════════════════
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop SQLite init
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Android: request Bluetooth + Location permissions before anything else
  if (Platform.isAndroid) {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
      Permission.locationWhenInUse,
    ].request();
    if (kDebugMode) {
      statuses.forEach((perm, status) {
        print('[Permission] $perm → $status');
      });
    }
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

// ══════════════════════════════════════════════════════════════
//  COLORS
// ══════════════════════════════════════════════════════════════
class K {
  static const bg = Color(0xFF060D08);
  static const surface = Color(0xFF0B1510);
  static const card = Color(0xFF0F1C12);
  static const cardHi = Color(0xFF152118);
  static const border = Color(0xFF1A2B1E);
  static const borderHi = Color(0xFF274035);

  static const green = Color(0xFF00E676);
  static const greenGlow = Color(0x3300E676);
  static const teal = Color(0xFF00BCD4);
  static const tealGlow = Color(0x2500BCD4);
  static const amber = Color(0xFFFFB300);
  static const amberGlow = Color(0x25FFB300);
  static const red = Color(0xFFFF1744);
  static const redGlow = Color(0x2EFF1744);
  static const blue = Color(0xFF448AFF);
  static const gold = Color(0xFFFFD600);
  static const purple = Color(0xFFCE93D8);

  static const t1 = Color(0xFFE8F5E9);
  static const t2 = Color(0xFF81C784);
  static const t3 = Color(0xFF2E4A32);
  static const t4 = Color(0xFF182A1A);
}

// ══════════════════════════════════════════════════════════════
//  APP
// ══════════════════════════════════════════════════════════════
class FarmLinkApp extends StatelessWidget {
  const FarmLinkApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FarmLink',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: K.bg,
      colorScheme: const ColorScheme.dark(primary: K.green, surface: K.surface),
      useMaterial3: true,
    ),
    home: const _Splash(),
  );
}

// ══════════════════════════════════════════════════════════════
//  SPLASH
// ══════════════════════════════════════════════════════════════
class _Splash extends StatefulWidget {
  const _Splash();
  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..forward();
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, .6),
  );
  late final Animation<double> _rise = Tween<double>(
    begin: 48,
    end: 0,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2700), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const _Dashboard(),
          transitionsBuilder: (_, a, __, c) =>
              FadeTransition(opacity: a, child: c),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: K.bg,
    body: Center(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => FadeTransition(
          opacity: _fade,
          child: Transform.translate(
            offset: Offset(0, _rise.value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: K.green.withOpacity(.07),
                    border: Border.all(
                      color: K.green.withOpacity(.35),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: K.greenGlow,
                        blurRadius: 60,
                        spreadRadius: 12,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text('🌿', style: TextStyle(fontSize: 54)),
                  ),
                ),
                const SizedBox(height: 32),
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [K.green, K.teal],
                  ).createShader(b),
                  child: const Text(
                    'FARMLINK',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'SMART PLANT MONITOR',
                  style: TextStyle(fontSize: 11, color: K.t3, letterSpacing: 4),
                ),
                const SizedBox(height: 56),
                SizedBox(
                  width: 110,
                  child: LinearProgressIndicator(
                    backgroundColor: K.border,
                    color: K.green,
                    minHeight: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════
//  DASHBOARD
// ══════════════════════════════════════════════════════════════
class _Dashboard extends StatefulWidget {
  const _Dashboard();
  @override
  State<_Dashboard> createState() => _DashState();
}

class _DashState extends State<_Dashboard> with TickerProviderStateMixin {
  final _bt = BluetoothService();
  final _db = SensorDatabase.instance;

  PlantData _d = PlantData.initial();
  bool _connected = false;
  bool _connecting = false;
  bool _manual = false;
  int _tab = 0;

  StreamSubscription<String>? _sub;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _db.prune();
    _connect();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _spin.dispose();
    _sub?.cancel();
    _bt.dispose();
    super.dispose();
  }

  // ── BLUETOOTH ────────────────────────────────────────────
  Future<void> _connect() async {
    if (_connecting) return;
    setState(() => _connecting = true);
    final ok = await _bt.scanAndConnect();
    if (ok) {
      _sub = _bt.dataStream.listen(
        _onLine,
        onError: (_) => setState(() => _connected = false),
      );
    }
    setState(() {
      _connected = ok;
      _connecting = false;
    });
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'HC-05 not found. Pair "FarmLink_BT" first in Bluetooth settings.',
          ),
          backgroundColor: K.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  void _onLine(String line) {
    final clean = line.replaceAll('\r', '').trim();
    if (clean.isEmpty) return;
    if (clean.split(',').length != 8) {
      if (kDebugMode) print('[App] Skipping malformed: "$clean"');
      return;
    }
    try {
      final p = PlantData.fromRawString(clean);
      if (kDebugMode) print('[App] $p');
      setState(() => _d = p);
      _db.insert(p);
    } catch (e) {
      if (kDebugMode) print('[App] Parse error: $e  raw="$clean"');
    }
  }

  Future<void> _togglePump(bool v) async {
    setState(() => _manual = v);
    await _bt.sendCommand(v ? '1' : '0');
  }

  // ── DERIVED STATE (mirrors Arduino logic exactly) ────────
  bool get _tankEmpty => _d.waterLevel <= kWaterLowThresh;
  bool get _soilNotOpt => _d.moisture < kSoilMoistureLow;
  bool get _soilHot => _d.soilTemp > kSoilTempHigh && _d.soilTemp != -1;
  bool get _airHot => _d.airTemp >= kAirTempHot && _d.airTemp != -1;
  bool get _pumpActive => _d.pumpStatus == 1;
  bool get _motionOn => _d.motion == 1;

  // System status mirrors exactly what Arduino decides
  String get _statusText {
    if (!_connected) return 'DISCONNECTED';
    if (_tankEmpty) return 'TANK EMPTY';
    if (_pumpActive) return _manual ? 'MANUAL PUMP ON' : 'AUTO IRRIGATING';
    if (_airHot) return 'AIR TOO HOT';
    if (_soilHot) return 'SOIL TOO HOT';
    if (_soilNotOpt) return 'SOIL DRY';
    return 'ALL OPTIMAL';
  }

  Color get _statusColor {
    if (!_connected) return K.t3;
    if (_tankEmpty) return K.red;
    if (_pumpActive) return K.teal;
    if (_airHot) return K.red;
    if (_soilHot) return K.amber;
    if (_soilNotOpt) return K.amber;
    return K.green;
  }

  // ── BUILD ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: K.bg,
      body: Stack(
        children: [
          // Ambient glow
          Positioned(
            top: -130,
            right: -130,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [K.green.withOpacity(.035), Colors.transparent],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _topBar(),
                Expanded(
                  child: _tab == 0 ? _dashBody() : const _HistoryScreen(),
                ),
                _navBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── TOP BAR ──────────────────────────────────────────────
  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: K.green.withOpacity(.09),
              border: Border.all(color: K.green.withOpacity(.3)),
              boxShadow: [BoxShadow(color: K.greenGlow, blurRadius: 20)],
            ),
            child: const Center(
              child: Text('🌿', style: TextStyle(fontSize: 21)),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                  colors: [K.green, K.teal],
                ).createShader(b),
                child: const Text(
                  'FARMLINK',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 4,
                  ),
                ),
              ),
              const Text(
                'Smart Plant Monitor',
                style: TextStyle(fontSize: 9, color: K.t3, letterSpacing: 1),
              ),
            ],
          ),
          const Spacer(),
          // BT status badge — tap to reconnect when offline
          GestureDetector(
            onTap: (!_connected && !_connecting) ? _connect : null,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _statusColor.withOpacity(
                      _connecting ? .2 + .5 * _pulse.value : .35,
                    ),
                  ),
                  boxShadow: _connected
                      ? [
                          BoxShadow(
                            color: _statusColor.withOpacity(.1),
                            blurRadius: 12,
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_connecting)
                      RotationTransition(
                        turns: _spin,
                        child: const Icon(Icons.sync, size: 11, color: K.amber),
                      )
                    else
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _statusColor,
                          boxShadow: [
                            BoxShadow(
                              color: _statusColor.withOpacity(
                                _connected ? _pulse.value * .8 : .2,
                              ),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(width: 7),
                    Text(
                      _connecting
                          ? 'SCANNING…'
                          : _connected
                          ? 'ONLINE'
                          : 'TAP TO CONNECT',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: _connecting ? K.amber : _statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── DASHBOARD BODY ───────────────────────────────────────
  Widget _dashBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        children: [
          _heroCard(),
          const SizedBox(height: 14),
          _pumpCard(),
          const SizedBox(height: 14),
          _alertRow(),
          const SizedBox(height: 14),
          _sensorGrid(),
          const SizedBox(height: 14),
          _motionCard(),
        ],
      ),
    );
  }

  // ── HERO STATUS CARD ─────────────────────────────────────
  Widget _heroCard() {
    return _GlowCard(
      accent: _statusColor,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _lbl('SYSTEM STATUS'),
                const SizedBox(height: 6),
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => Text(
                    _statusText,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: _statusColor,
                      shadows: [
                        Shadow(
                          color: _statusColor.withOpacity(
                            _pumpActive ? _pulse.value * .5 : .25,
                          ),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Quick stats
                Wrap(
                  spacing: 18,
                  children: [
                    _qStat(
                      '🌡',
                      '${_d.airTemp.toStringAsFixed(1)}°C',
                      _airHot ? K.red : K.amber,
                    ),
                    _qStat('💧', '${_d.airHumid.toStringAsFixed(0)}%', K.blue),
                    _qStat('☀️', '${_d.light}%', K.gold),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _MoistureRing(
            percent: _d.moisture,
            color: _soilNotOpt ? K.amber : K.green,
            threshold: kSoilMoistureLow,
          ),
        ],
      ),
    );
  }

  Widget _qStat(String icon, String val, Color c) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(icon, style: const TextStyle(fontSize: 14)),
      const SizedBox(width: 4),
      Text(
        val,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c),
      ),
    ],
  );

  // ── PUMP CARD ────────────────────────────────────────────
  Widget _pumpCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: _pumpActive
              ? [const Color(0xFF041D28), const Color(0xFF063344)]
              : [K.card, K.cardHi],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: _pumpActive ? K.teal.withOpacity(.4) : K.border,
        ),
        boxShadow: _pumpActive
            ? [BoxShadow(color: K.tealGlow, blurRadius: 28)]
            : [],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              // Animated pump icon
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
                    color: (_pumpActive ? K.teal : K.t3).withOpacity(.1),
                    border: Border.all(
                      color: (_pumpActive ? K.teal : K.t3).withOpacity(
                        _pumpActive ? .25 + .35 * _pulse.value : .15,
                      ),
                    ),
                    boxShadow: _pumpActive
                        ? [
                            BoxShadow(
                              color: K.teal.withOpacity(_pulse.value * .3),
                              blurRadius: 22,
                            ),
                          ]
                        : [],
                  ),
                  child: Icon(
                    Icons.water,
                    color: _pumpActive ? K.teal : K.t3,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl('WATER PUMP'),
                    const SizedBox(height: 5),
                    Text(
                      _tankEmpty
                          ? 'Tank empty — pump blocked'
                          : _pumpActive
                          ? (_manual
                                ? 'Manual override active'
                                : 'Auto-irrigating…')
                          : 'Standby — conditions optimal',
                      style: TextStyle(
                        fontSize: 14,
                        color: _tankEmpty
                            ? K.red
                            : _pumpActive
                            ? K.teal
                            : K.t2,
                      ),
                    ),
                  ],
                ),
              ),
              // Manual override switch
              Column(
                children: [
                  _lbl('OVERRIDE'),
                  const SizedBox(height: 4),
                  Switch.adaptive(
                    value: _manual,
                    onChanged: _tankEmpty ? null : _togglePump,
                    activeColor: K.teal,
                    activeTrackColor: K.teal.withOpacity(.2),
                    inactiveThumbColor: K.t3,
                    inactiveTrackColor: K.bg,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Reservoir level bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _lbl('RESERVOIR LEVEL'),
              Text(
                '${_d.waterLevel}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _tankEmpty
                      ? K.red
                      : _d.waterLevel < 30
                      ? K.amber
                      : K.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(
                begin: 0,
                end: (_d.waterLevel / 100).clamp(0.0, 1.0),
              ),
              duration: const Duration(milliseconds: 700),
              builder: (_, v, __) => LinearProgressIndicator(
                value: v,
                minHeight: 9,
                backgroundColor: K.bg,
                valueColor: AlwaysStoppedAnimation(
                  _tankEmpty
                      ? K.red
                      : _d.waterLevel < 30
                      ? K.amber
                      : K.teal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── ALERT ROW: soil temp + air temp ──────────────────────
  Widget _alertRow() {
    return Row(
      children: [
        Expanded(
          child: _alertTile(
            emoji: '🌱',
            label: 'SOIL TEMP',
            value: '${_d.soilTemp.toStringAsFixed(1)}°C',
            sub: _soilHot
                ? '▲ Above ${kSoilTempHigh.toStringAsFixed(0)}°C'
                : 'Normal',
            color: _soilHot ? K.red : K.green,
            active: _soilHot,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _alertTile(
            emoji: '🌬',
            label: 'AIR TEMP',
            value: '${_d.airTemp.toStringAsFixed(1)}°C',
            sub: _airHot
                ? '▲ Above ${kAirTempHot.toStringAsFixed(0)}°C'
                : 'Normal',
            color: _airHot ? K.red : K.amber,
            active: _airHot,
          ),
        ),
      ],
    );
  }

  Widget _alertTile({
    required String emoji,
    required String label,
    required String value,
    required String sub,
    required Color color,
    required bool active,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: K.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? color.withOpacity(.4) : K.border),
        boxShadow: active
            ? [BoxShadow(color: color.withOpacity(.15), blurRadius: 16)]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              _lbl(label),
              if (active) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withOpacity(.4)),
                  ),
                  child: Text(
                    'ALERT',
                    style: TextStyle(
                      fontSize: 8,
                      color: color,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: color,
              shadows: [Shadow(color: color.withOpacity(.3), blurRadius: 10)],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: TextStyle(fontSize: 10, color: color.withOpacity(.7)),
          ),
        ],
      ),
    );
  }

  // ── SENSOR GRID ──────────────────────────────────────────
  Widget _sensorGrid() {
    final items = [
      _SI(
        'SOIL MOISTURE',
        '${_d.moisture}%',
        Icons.water_drop,
        K.green,
        (_d.moisture / 100).clamp(0.0, 1.0).toDouble(),
        warn: _soilNotOpt,
        warnLabel: 'DRY',
      ),
      _SI(
        'AIR HUMIDITY',
        '${_d.airHumid.toStringAsFixed(0)}%',
        Icons.cloud,
        K.blue,
        (_d.airHumid / 100).clamp(0.0, 1.0).toDouble(),
      ),
      _SI(
        'LIGHT LEVEL',
        '${_d.light}%',
        Icons.wb_sunny,
        K.gold,
        (_d.light / 100).clamp(0.0, 1.0).toDouble(),
      ),
      _SI(
        'TANK LEVEL',
        '${_d.waterLevel}%',
        Icons.waves,
        K.teal,
        (_d.waterLevel / 100).clamp(0.0, 1.0).toDouble(),
        warn: _tankEmpty,
        warnLabel: 'EMPTY',
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.08,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _SensorCard(info: items[i]),
    );
  }

  // ── MOTION + BUZZER CARD ─────────────────────────────────
  // In your Arduino: buzzer ON when motion detected
  Widget _motionCard() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: K.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _motionOn ? K.amber.withOpacity(.5) : K.border,
          ),
          boxShadow: _motionOn
              ? [BoxShadow(color: K.amberGlow, blurRadius: 20)]
              : [],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: (_motionOn ? K.amber : K.t3).withOpacity(.1),
                border: Border.all(
                  color: (_motionOn ? K.amber : K.t3).withOpacity(.2),
                ),
              ),
              child: Icon(
                _motionOn ? Icons.directions_run : Icons.sensors,
                color: _motionOn ? K.amber : K.t3,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _lbl('PIR MOTION SENSOR'),
                  const SizedBox(height: 4),
                  Text(
                    _motionOn ? 'MOVEMENT DETECTED' : 'No activity',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _motionOn ? K.amber : K.t3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Show buzzer status — matches Arduino buzzer logic
                  Row(
                    children: [
                      Icon(
                        _motionOn ? Icons.volume_up : Icons.volume_off,
                        size: 12,
                        color: _motionOn ? K.amber : K.t3,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _motionOn
                            ? 'Buzzer sounding on hardware'
                            : 'Buzzer silent',
                        style: TextStyle(
                          fontSize: 10,
                          color: _motionOn ? K.amber.withOpacity(.8) : K.t3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Pulsing dot
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _motionOn ? K.amber : K.t3,
                boxShadow: _motionOn
                    ? [
                        BoxShadow(
                          color: K.amber.withOpacity(_pulse.value * .8),
                          blurRadius: 10,
                        ),
                      ]
                    : [],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── NAV BAR ──────────────────────────────────────────────
  Widget _navBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: K.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: K.border),
      ),
      child: Row(
        children: [
          _NavBtn(
            Icons.dashboard_rounded,
            'Dashboard',
            _tab == 0,
            () => setState(() => _tab = 0),
          ),
          _NavBtn(
            Icons.history_rounded,
            'History',
            _tab == 1,
            () => setState(() => _tab = 1),
          ),
        ],
      ),
    );
  }

  Widget _lbl(String t) => Text(
    t,
    style: const TextStyle(
      fontSize: 9,
      letterSpacing: 2,
      color: K.t3,
      fontWeight: FontWeight.w600,
    ),
  );
}

// ══════════════════════════════════════════════════════════════
//  GLOW CARD WRAPPER
// ══════════════════════════════════════════════════════════════
class _GlowCard extends StatelessWidget {
  final Widget child;
  final Color accent;
  const _GlowCard({required this.child, required this.accent});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: K.card,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: accent.withOpacity(.25)),
      boxShadow: [BoxShadow(color: accent.withOpacity(.07), blurRadius: 24)],
    ),
    child: child,
  );
}

// ══════════════════════════════════════════════════════════════
//  SENSOR CARD
// ══════════════════════════════════════════════════════════════
class _SI {
  final String label, value;
  final IconData icon;
  final Color color;
  final double bar;
  final bool warn;
  final String? warnLabel;
  const _SI(
    this.label,
    this.value,
    this.icon,
    this.color,
    this.bar, {
    this.warn = false,
    this.warnLabel,
  });
}

class _SensorCard extends StatelessWidget {
  final _SI info;
  const _SensorCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final c = info.warn ? K.red : info.color;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: K.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: info.warn ? K.red.withOpacity(.35) : K.border,
        ),
        boxShadow: info.warn
            ? [BoxShadow(color: K.redGlow, blurRadius: 14)]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: c.withOpacity(.1),
                  border: Border.all(color: c.withOpacity(.2)),
                ),
                child: Icon(info.icon, color: c, size: 20),
              ),
              if (info.warn && info.warnLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: K.red.withOpacity(.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: K.red.withOpacity(.4)),
                  ),
                  child: Text(
                    info.warnLabel!,
                    style: const TextStyle(
                      fontSize: 8,
                      color: K.red,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
            ],
          ),
          Text(
            info.value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: c,
              shadows: [Shadow(color: c.withOpacity(.3), blurRadius: 10)],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                info.label,
                style: const TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.5,
                  color: K.t3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: info.bar.clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 700),
                  builder: (_, v, __) => LinearProgressIndicator(
                    value: v,
                    minHeight: 4,
                    backgroundColor: c.withOpacity(.1),
                    valueColor: AlwaysStoppedAnimation(c),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  MOISTURE RING
// ══════════════════════════════════════════════════════════════
class _MoistureRing extends StatelessWidget {
  final int percent;
  final Color color;
  final int threshold;
  const _MoistureRing({
    required this.percent,
    required this.color,
    required this.threshold,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 90,
    height: 90,
    child: Stack(
      alignment: Alignment.center,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: percent / 100),
          duration: const Duration(milliseconds: 900),
          builder: (_, v, __) => CustomPaint(
            size: const Size(90, 90),
            painter: _RingPainter(v, color),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$percent',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
                shadows: [Shadow(color: color.withOpacity(.5), blurRadius: 12)],
              ),
            ),
            Text(
              '%',
              style: TextStyle(fontSize: 10, color: color.withOpacity(.5)),
            ),
          ],
        ),
      ],
    ),
  );
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color c;
  const _RingPainter(this.v, this.c);

  @override
  void paint(Canvas canvas, Size s) {
    final ctr = Offset(s.width / 2, s.height / 2);
    final r = s.width / 2 - 6;
    canvas.drawCircle(
      ctr,
      r,
      Paint()
        ..color = c.withOpacity(.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    canvas.drawArc(
      Rect.fromCircle(center: ctr, radius: r),
      -pi / 2,
      2 * pi * v,
      false,
      Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 1.5),
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v;
}

// ══════════════════════════════════════════════════════════════
//  NAV BUTTON
// ══════════════════════════════════════════════════════════════
class _NavBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool sel;
  final VoidCallback onTap;
  const _NavBtn(this.icon, this.label, this.sel, this.onTap);

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: sel ? K.green.withOpacity(.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          border: sel ? Border.all(color: K.green.withOpacity(.25)) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: sel ? K.green : K.t3, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: sel ? K.t2 : K.t3,
                fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════
//  HISTORY SCREEN
// ══════════════════════════════════════════════════════════════
class _HistoryScreen extends StatefulWidget {
  const _HistoryScreen();
  @override
  State<_HistoryScreen> createState() => _HistState();
}

class _HistState extends State<_HistoryScreen> {
  final _db = SensorDatabase.instance;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _db.recent();
    setState(() {
      _rows = r;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: Row(
            children: [
              const Text(
                'SENSOR LOG',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: K.t1,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  await _db.clear();
                  _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: K.red.withOpacity(.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: K.red.withOpacity(.3)),
                  ),
                  child: const Text(
                    'CLEAR',
                    style: TextStyle(
                      fontSize: 10,
                      color: K.red,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: K.green))
              : _rows.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🌱', style: TextStyle(fontSize: 52)),
                      const SizedBox(height: 14),
                      const Text(
                        'No readings yet',
                        style: TextStyle(color: K.t2, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Connect to Arduino to start logging',
                        style: TextStyle(color: K.t3, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _HRow(row: _rows[i]),
                ),
        ),
      ],
    );
  }
}

class _HRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _HRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final ts = DateTime.tryParse(row['ts'] ?? '');
    final time = ts != null
        ? '${ts.hour.toString().padLeft(2, '0')}:'
              '${ts.minute.toString().padLeft(2, '0')}:'
              '${ts.second.toString().padLeft(2, '0')}'
        : '--:--:--';
    final date = ts != null
        ? '${ts.day.toString().padLeft(2, '0')}/'
              '${ts.month.toString().padLeft(2, '0')}'
        : '';
    final moist = row['moisture'] as int? ?? 0;
    final water = row['water_level'] as int? ?? 0;
    final airT = (row['air_temp'] as double?)?.toStringAsFixed(1) ?? '--';
    final soilT = (row['soil_temp'] as double?)?.toStringAsFixed(1) ?? '--';
    final humid = (row['air_humid'] as double?)?.toStringAsFixed(0) ?? '--';
    final pump = (row['pump'] as int? ?? 0) == 1;
    final motion = (row['motion'] as int? ?? 0) == 1;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: K.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: K.border),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                time,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: K.t1,
                ),
              ),
              Text(date, style: const TextStyle(fontSize: 10, color: K.t3)),
            ],
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 38, color: K.border),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                _chip(
                  '💧 $moist%',
                  moist < kSoilMoistureLow ? K.amber : K.green,
                ),
                _chip('💦 $water%', water <= kWaterLowThresh ? K.red : K.teal),
                _chip('🌡 $airT°C', K.amber),
                _chip('🌱 $soilT°C', K.green),
                _chip('💨 $humid%', K.blue),
                if (motion) _chip('🏃 Motion', K.amber),
                _chip(pump ? '⚡ Pump ON' : '— Idle', pump ? K.teal : K.t3),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c.withOpacity(.1),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: c.withOpacity(.3)),
    ),
    child: Text(
      t,
      style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w600),
    ),
  );
}
