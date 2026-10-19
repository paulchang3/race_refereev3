import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'cert.dart';
import 'engine.dart';
import 'player_page.dart';

class Player {
  Player(this.id, this.name);
  final String id;
  String name;
  WebSocket? socket;
  bool get connected => socket != null;
}

/// 在手機上跑的小型 https + WebSocket 伺服器：
/// GET /   → 選手頁面（掃 QR 開啟）
/// /ws     → 選手回傳感測器資料、接收狀態與震動指令
class HostServer extends ChangeNotifier {
  HostServer(this.engine) {
    engine.onVibrate = _vibrate;
    engine.onStatusChanged = broadcastStatus;
  }

  static const int maxPlayers = 20;

  final RaceEngine engine;
  final Map<String, Player> players = {};
  HttpServer? _http;
  List<String> addresses = [];
  int addressIndex = 0;
  int port = 0;
  String? error;
  Phase _lastPhase = Phase.lobby;

  String get url {
    if (addresses.isEmpty || port == 0) return '';
    return 'https://${addresses[addressIndex % addresses.length]}:$port/';
  }

  void nextAddress() {
    if (addresses.length > 1) {
      addressIndex = (addressIndex + 1) % addresses.length;
      notifyListeners();
    }
  }

  Future<void> start() async {
    try {
      final ctx = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(kCertPem))
        ..usePrivateKeyBytes(utf8.encode(kKeyPem));
      for (var p = 8443; p < 8453 && _http == null; p++) {
        try {
          _http = await HttpServer.bindSecure(InternetAddress.anyIPv4, p, ctx);
          port = p;
        } on SocketException {
          // 埠被占用，試下一個
        }
      }
      if (_http == null) throw StateError('找不到可用的埠（8443–8452）');
      _http!.listen(_handle, onError: (_) {}); // 瀏覽器拒絕憑證時會有握手錯誤，忽略
      await refreshAddresses();
    } catch (e) {
      error = '伺服器啟動失敗：$e';
    }
    notifyListeners();
  }

  Future<void> refreshAddresses() async {
    final found = <String>[];
    try {
      for (final i in await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false)) {
        for (final a in i.addresses) {
          found.add(a.address);
        }
      }
    } catch (_) {}
    int rank(String a) {
      if (a.startsWith('192.168.')) return 0;
      if (a.startsWith('10.')) return 1;
      final m = RegExp(r'^172\.(\d+)\.').firstMatch(a);
      if (m != null && int.parse(m.group(1)!) >= 16 && int.parse(m.group(1)!) <= 31) return 2;
      return 3;
    }

    found.sort((a, b) => rank(a).compareTo(rank(b)));
    addresses = found;
    if (addressIndex >= addresses.length) addressIndex = 0;
    notifyListeners();
  }

  Future<void> stop() async {
    for (final p in players.values) {
      await p.socket?.close();
    }
    await _http?.close(force: true);
  }

  // ------------------------------------------------------------ HTTP
  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (path == '/ws' && WebSocketTransformer.isUpgradeRequest(req)) {
        final ws = await WebSocketTransformer.upgrade(req);
        _onSocket(ws);
      } else if (path == '/' || path == '/index.html') {
        req.response.headers.contentType = ContentType('text', 'html', charset: 'utf-8');
        req.response.headers.set('Cache-Control', 'no-store');
        req.response.write(kPlayerPage);
        await req.response.close();
      } else {
        req.response.statusCode = path == '/favicon.ico' ? 204 : 404;
        await req.response.close();
      }
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------ WebSocket
  void _onSocket(WebSocket ws) {
    ws.pingInterval = const Duration(seconds: 5); // 偵測手機斷線
    Player? me;
    ws.listen((data) {
      if (data is! String) return;
      final Map<String, dynamic> m;
      try {
        final d = jsonDecode(data);
        if (d is! Map) return;
        m = d.cast<String, dynamic>();
      } catch (_) {
        return;
      }
      switch (m['t']) {
        case 'hello':
          me = _hello(ws, m);
        case 's':
          final p = me;
          if (p != null) _sample(p, m);
      }
    }, onDone: () => _closed(me, ws), onError: (_) => _closed(me, ws), cancelOnError: true);
  }

  Player? _hello(WebSocket ws, Map<String, dynamic> m) {
    final id = _clean(m['id'], 64);
    if (id.isEmpty) return null;
    final name = _clean(m['name'], 12);
    var p = players[id];
    if (p == null) {
      if (players.length >= maxPlayers) {
        _send(ws, {'t': 'full'});
        ws.close();
        return null;
      }
      p = Player(id, name.isEmpty ? '選手${players.length + 1}' : name);
      players[id] = p;
    } else if (name.isNotEmpty) {
      p.name = name;
    }
    final old = p.socket;
    p.socket = ws;
    if (old != null && old != ws) old.close();

    final busy = engine.phase == Phase.racing || engine.phase == Phase.countdown;
    if (engine.laneOf(p.id) < 0 && !busy) engine.assignLane(p.id);
    _refresh();
    broadcastStatus();
    return p;
  }

  void _closed(Player? p, WebSocket ws) {
    if (p == null || p.socket != ws) return; // 已被新連線取代
    p.socket = null;
    _refresh();
    // 大廳裡斷線給 8 秒重連機會，之後移除並讓候補遞補
    Timer(const Duration(seconds: 8), () {
      final stillGone = p.socket == null && players[p.id] == p;
      if (stillGone && (engine.phase == Phase.lobby)) {
        _remove(p.id);
      }
    });
  }

  void _sample(Player p, Map<String, dynamic> m) {
    final lane = engine.laneOf(p.id);
    if (lane < 0) return;
    engine.feed(lane,
        rx: _num(m['rx']),
        ry: _num(m['ry']),
        rz: _num(m['rz']),
        lx: _num(m['lx']),
        ly: _num(m['ly']),
        lz: _num(m['lz']));
  }

  // ------------------------------------------------------------ 玩家管理
  void kick(String id) {
    final p = players[id];
    p?.socket?.close();
    _remove(id);
  }

  void _remove(String id) {
    players.remove(id);
    engine.releaseLane(id);
    _promoteWaiting();
    _refresh();
    broadcastStatus();
  }

  void _promoteWaiting() {
    if (engine.phase == Phase.racing || engine.phase == Phase.countdown) return;
    for (final p in players.values) {
      if (p.connected && engine.laneOf(p.id) < 0) engine.assignLane(p.id);
    }
  }

  /// 回到大廳時，把已斷線的人清掉。
  void sweepDisconnected() {
    final gone = players.values.where((p) => !p.connected).map((p) => p.id).toList();
    for (final id in gone) {
      players.remove(id);
      engine.releaseLane(id);
    }
    _promoteWaiting();
    _refresh();
  }

  void _refresh() {
    for (final l in engine.lanes) {
      final p = l.playerId == null ? null : players[l.playerId];
      if (p != null) {
        l.name = p.name;
        l.connected = p.connected;
      } else if (l.playerId != null && p == null) {
        l.connected = false;
      }
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ 推送
  void broadcastStatus() {
    if (engine.phase == Phase.lobby && _lastPhase != Phase.lobby) sweepDisconnected();
    _lastPhase = engine.phase;
    _refresh();
    for (final p in players.values) {
      final lane = engine.laneOf(p.id);
      _send(p.socket, {
        't': 'status',
        'phase': engine.phase.name,
        'lane': lane,
        'label': lane < 0 ? '' : engine.lanes[lane].label,
        'name': p.name,
      });
    }
  }

  void _vibrate(int lane, List<int> pattern) {
    final id = engine.lanes[lane].playerId;
    if (id == null) return;
    _send(players[id]?.socket, {'t': 'vib', 'p': pattern});
  }

  void _send(WebSocket? ws, Map<String, dynamic> msg) {
    if (ws == null) return;
    try {
      ws.add(jsonEncode(msg));
    } catch (_) {}
  }

  static String _clean(Object? v, int max) {
    final s = (v is String ? v : '')
        .replaceAll(RegExp(r'[\x00-\x1f\x7f\u200b-\u200f\u2028-\u202e]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return s.length > max ? s.substring(0, max) : s;
  }

  static double _num(Object? v) {
    if (v is num && v.isFinite) return v.toDouble().clamp(-5000.0, 5000.0).toDouble();
    return 0;
  }
}
