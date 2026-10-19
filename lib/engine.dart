import 'dart:math' as math;
import 'package:flutter/foundation.dart';

enum Phase { lobby, countdown, racing, finished }

enum SignalSource { gyro, shake, both }

const double trackMeters = 100;
const double gyroFullScale = 720; // °/s，陀螺儀滿格
const double shakeFullScale = 30; // m/s²，震動（線性加速度）滿格
const double maxSpeed = 8.0; // 靈敏度 ×1、訊號滿格時的速度 m/s
const double hardCapSpeed = 12.0; // 速度上限 m/s
const int histLen = 150; // 圖表保留幾個點（約 5 秒）
const double _envTau = 0.30; // 峰值包絡的衰減時間（秒）：揮手訊號是來回擺動，取包絡才不會一抖一停
const double _speedTau = 0.25; // 速度追上目標的時間（秒）

class Lane {
  Lane(this.index);

  final int index;
  String? playerId;
  String name = '';
  bool connected = false;

  // 裁判可調
  double gain = 1.0;
  double deadzone = 0.15; // 0..0.6，占滿格的比例
  SignalSource source = SignalSource.both;

  // 原始訊號（最後一筆）
  double rx = 0, ry = 0, rz = 0, lx = 0, ly = 0, lz = 0;
  double gyro = 0, shake = 0;
  double gyroPeak = 0, shakePeak = 0;
  int lastSampleMs = 0;

  // 轉換結果
  double norm = 0, env = 0, power = 0, speed = 0, distance = 0, stride = 0;
  double? finishTime;

  // 靜止校準
  double calibRemain = 0;
  final List<double> calib = [];

  final List<double> gyroHist = [];
  final List<double> shakeHist = [];

  bool get hasPlayer => playerId != null;
  String get label => index == 0 ? 'A' : 'B';

  void resetRace() {
    distance = 0;
    speed = 0;
    env = 0;
    power = 0;
    stride = 0;
    finishTime = null;
  }

  void resetSignals() {
    rx = ry = rz = lx = ly = lz = 0;
    gyro = shake = gyroPeak = shakePeak = 0;
    lastSampleMs = 0;
    gyroHist.clear();
    shakeHist.clear();
  }
}

class RaceEngine extends ChangeNotifier {
  final List<Lane> lanes = [Lane(0), Lane(1)];
  Phase phase = Phase.lobby;
  double countdown = 0;
  double raceTime = 0;
  double? _firstFinish;
  int _lastCountInt = 99;

  /// 要求某條跑道的手機震動。
  void Function(int lane, List<int> pattern)? onVibrate;

  /// 階段或跑道指派改變時通知（伺服器會把狀態推給手機）。
  void Function()? onStatusChanged;

  bool get canStart =>
      phase == Phase.lobby && lanes.every((l) => l.hasPlayer && l.connected);

  int laneOf(String playerId) => lanes.indexWhere((l) => l.playerId == playerId);

  void touch() => notifyListeners();

  // ------------------------------------------------------------ 跑道指派
  int assignLane(String playerId) {
    final existing = laneOf(playerId);
    if (existing >= 0) return existing;
    final free = lanes.indexWhere((l) => !l.hasPlayer);
    if (free < 0) return -1;
    lanes[free]
      ..playerId = playerId
      ..resetSignals()
      ..resetRace();
    return free;
  }

  void releaseLane(String playerId) {
    final i = laneOf(playerId);
    if (i < 0) return;
    lanes[i]
      ..playerId = null
      ..name = ''
      ..connected = false
      ..resetSignals()
      ..resetRace();
  }

  void swapLanes() {
    if (phase != Phase.lobby) return;
    final a = lanes[0], b = lanes[1];
    final id = a.playerId;
    a.playerId = b.playerId;
    b.playerId = id;
    final nm = a.name;
    a.name = b.name;
    b.name = nm;
    final cn = a.connected;
    a.connected = b.connected;
    b.connected = cn;
    a.resetSignals();
    b.resetSignals();
    onStatusChanged?.call();
    notifyListeners();
  }

  // ------------------------------------------------------------ 訊號輸入
  void feed(int laneIdx,
      {required double rx,
      required double ry,
      required double rz,
      required double lx,
      required double ly,
      required double lz}) {
    final l = lanes[laneIdx];
    l.rx = rx;
    l.ry = ry;
    l.rz = rz;
    l.lx = lx;
    l.ly = ly;
    l.lz = lz;
    l.gyro = math.sqrt(rx * rx + ry * ry + rz * rz);
    l.shake = math.sqrt(lx * lx + ly * ly + lz * lz);
    l.gyroPeak = math.max(l.gyroPeak, l.gyro);
    l.shakePeak = math.max(l.shakePeak, l.shake);
    l.lastSampleMs = DateTime.now().millisecondsSinceEpoch;
  }

  // ------------------------------------------------------------ 校準
  void startCalibration(Lane l) {
    if (!l.hasPlayer) return;
    l.calib.clear();
    l.calibRemain = 2.0;
    l.gyroPeak = 0;
    l.shakePeak = 0;
    notifyListeners();
  }

  void _finishCalibration(Lane l) {
    if (l.calib.isNotEmpty) {
      final mean = l.calib.reduce((a, b) => a + b) / l.calib.length;
      final variance = l.calib
              .map((v) => (v - mean) * (v - mean))
              .reduce((a, b) => a + b) /
          l.calib.length;
      l.deadzone = (mean + 3 * math.sqrt(variance) + 0.03).clamp(0.03, 0.6).toDouble();
    }
    l.calib.clear();
    l.gyroPeak = 0;
    l.shakePeak = 0;
  }

  // ------------------------------------------------------------ 比賽流程
  void start() {
    if (!canStart) return;
    for (final l in lanes) {
      l.resetRace();
    }
    raceTime = 0;
    _firstFinish = null;
    _lastCountInt = 99;
    countdown = 3.0;
    phase = Phase.countdown;
    onStatusChanged?.call();
    notifyListeners();
  }

  void backToLobby() {
    phase = Phase.lobby;
    for (final l in lanes) {
      l.resetRace();
      l.gyroPeak = 0;
      l.shakePeak = 0;
    }
    raceTime = 0;
    _firstFinish = null;
    onStatusChanged?.call();
    notifyListeners();
  }

  List<Lane> get ranking {
    final racers = lanes.where((l) => l.hasPlayer).toList();
    racers.sort((a, b) {
      final fa = a.finishTime, fb = b.finishTime;
      if (fa != null && fb != null) return fa.compareTo(fb);
      if (fa != null) return -1;
      if (fb != null) return 1;
      return b.distance.compareTo(a.distance);
    });
    return racers;
  }

  void tick(double dt) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    if (phase == Phase.countdown) {
      countdown -= dt;
      final n = countdown.ceil();
      if (countdown > 0 && n != _lastCountInt) {
        _lastCountInt = n;
        _vibrateAll(const [80]);
      }
      if (countdown <= 0) {
        phase = Phase.racing;
        raceTime = 0;
        _vibrateAll(const [400]);
        onStatusChanged?.call();
      }
    } else if (phase == Phase.racing) {
      raceTime += dt;
    }

    for (final l in lanes) {
      _updateLane(l, dt, nowMs);
    }

    if (phase == Phase.racing) {
      final racers = lanes.where((l) => l.hasPlayer).toList();
      final allDone = racers.isNotEmpty && racers.every((l) => l.finishTime != null);
      final timeout = _firstFinish != null && raceTime - _firstFinish! > 10;
      if (allDone || timeout) {
        phase = Phase.finished;
        onStatusChanged?.call();
      }
    }
    notifyListeners();
  }

  void _updateLane(Lane l, double dt, int nowMs) {
    final stale = nowMs - l.lastSampleMs > 600; // 超過 0.6 秒沒資料 → 當作靜止
    final g = stale ? 0.0 : l.gyro;
    final s = stale ? 0.0 : l.shake;
    final gN = (g / gyroFullScale).clamp(0.0, 1.0).toDouble();
    final sN = (s / shakeFullScale).clamp(0.0, 1.0).toDouble();
    final sel = switch (l.source) {
      SignalSource.gyro => gN,
      SignalSource.shake => sN,
      SignalSource.both => math.max(gN, sN),
    };
    l.norm = sel;
    l.env = math.max(sel, l.env * math.exp(-dt / _envTau));

    if (l.calibRemain > 0) {
      l.calib.add(sel);
      l.calibRemain -= dt;
      if (l.calibRemain <= 0) {
        l.calibRemain = 0;
        _finishCalibration(l);
      }
    }

    l.power = ((l.env - l.deadzone) / (1 - l.deadzone)).clamp(0.0, 1.0).toDouble();
    final finished = l.finishTime != null;
    final target = (finished || !l.hasPlayer)
        ? 0.0
        : math.min(l.power * l.gain * maxSpeed, hardCapSpeed);
    l.speed += (target - l.speed) * (1 - math.exp(-dt / _speedTau));
    if (l.speed < 0.01) l.speed = 0;
    l.stride += l.speed * dt * 1.4;

    if (phase == Phase.racing && l.hasPlayer && !finished) {
      l.distance += l.speed * dt;
      if (l.distance >= trackMeters) {
        final over = l.distance - trackMeters;
        l.distance = trackMeters;
        l.finishTime = raceTime - (l.speed > 0 ? over / l.speed : 0);
        if (_firstFinish == null) {
          _firstFinish = raceTime;
          onVibrate?.call(l.index, const [200, 100, 200, 100, 500]);
        } else {
          onVibrate?.call(l.index, const [300]);
        }
      }
    }

    l.gyroHist.add(gN);
    l.shakeHist.add(sN);
    if (l.gyroHist.length > histLen) l.gyroHist.removeAt(0);
    if (l.shakeHist.length > histLen) l.shakeHist.removeAt(0);
  }

  void _vibrateAll(List<int> p) {
    for (final l in lanes) {
      if (l.hasPlayer) onVibrate?.call(l.index, p);
    }
  }
}
