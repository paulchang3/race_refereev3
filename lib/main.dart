import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'engine.dart';
import 'host_server.dart';
import 'lobby_view.dart';
import 'race_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  WakelockPlus.enable(); // 裁判機不要休眠
  runApp(const RaceApp());
}

class RaceApp extends StatelessWidget {
  const RaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '百米賽跑・裁判台',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF22D3EE),
          brightness: Brightness.dark,
        ),
      ),
      home: const HostPage(),
    );
  }
}

class HostPage extends StatefulWidget {
  const HostPage({super.key});

  @override
  State<HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<HostPage> {
  late final RaceEngine engine = RaceEngine();
  late final HostServer server = HostServer(engine);
  final Stopwatch _clock = Stopwatch()..start();
  double _last = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    server.start();
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final t = _clock.elapsedMicroseconds / 1e6;
      final dt = (t - _last).clamp(0.0, 0.1).toDouble();
      _last = t;
      engine.tick(dt);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    server.stop();
    engine.dispose();
    server.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([engine, server]),
      builder: (context, _) => engine.phase == Phase.lobby
          ? LobbyView(engine: engine, server: server)
          : RaceView(engine: engine),
    );
  }
}
