import 'dart:ui' show FontFeature;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'engine.dart';
import 'lobby_view.dart' show laneColor, kPanel, kLine;

class RaceView extends StatelessWidget {
  const RaceView({super.key, required this.engine});

  final RaceEngine engine;

  @override
  Widget build(BuildContext context) {
    final phase = engine.phase;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(children: [
                const Text('🏁 百米賽跑',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                const Spacer(),
                Text(
                  phase == Phase.countdown ? '準備' : '${engine.raceTime.toStringAsFixed(2)} 秒',
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 12),
                if (phase != Phase.finished)
                  IconButton(
                    tooltip: '中止比賽',
                    onPressed: engine.backToLobby,
                    icon: const Icon(Icons.close),
                  ),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: CustomPaint(
                  painter: TrackPainter(engine),
                  size: Size.infinite,
                ),
              ),
            ),
          ]),
          if (phase == Phase.countdown) _countdown(),
          if (phase == Phase.racing && engine.raceTime < 0.8) _banner('GO!'),
          if (phase == Phase.finished) _results(),
        ]),
      ),
    );
  }

  Widget _countdown() {
    final n = engine.countdown.ceil().clamp(1, 3);
    return _banner('$n');
  }

  Widget _banner(String t) => IgnorePointer(
        child: Center(
          child: Text(
            t,
            style: const TextStyle(
              fontSize: 200,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              shadows: [Shadow(blurRadius: 24, color: Colors.black)],
            ),
          ),
        ),
      );

  Widget _results() {
    final rank = engine.ranking;
    const medals = ['🥇', '🥈'];
    return Container(
      color: const Color(0xCC050A14),
      alignment: Alignment.center,
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: kPanel,
          border: Border.all(color: kLine),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('比賽結果', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          for (var i = 0; i < rank.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Text(i < medals.length ? medals[i] : '${i + 1}', style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Text('${rank[i].label} 道',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: laneColor(rank[i].index))),
                const SizedBox(width: 10),
                Expanded(child: Text(rank[i].name, style: const TextStyle(fontSize: 22), overflow: TextOverflow.ellipsis)),
                Text(
                  rank[i].finishTime != null
                      ? '${rank[i].finishTime!.toStringAsFixed(2)} 秒'
                      : '${rank[i].distance.toStringAsFixed(1)} m（未完成）',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ]),
            ),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            onPressed: engine.backToLobby,
            child: const Text('回到賽前（再來一局）'),
          ),
        ]),
      ),
    );
  }
}

class TrackPainter extends CustomPainter {
  TrackPainter(this.engine);

  final RaceEngine engine;

  static const double _left = 110; // 跑道左側留給名字
  static const double _right = 50;

  @override
  void paint(Canvas canvas, Size size) {
    final laneH = size.height / 2;
    final x0 = _left;
    final x1 = size.width - _right;
    final span = x1 - x0;
    double xAt(double m) => x0 + span * (m / trackMeters);

    for (var i = 0; i < 2; i++) {
      final top = laneH * i;
      final rect = Rect.fromLTWH(0, top + 3, size.width, laneH - 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(10)),
        Paint()..color = i == 0 ? const Color(0xFF14202F) : const Color(0xFF191F2C),
      );
      // 距離刻度
      for (var m = 0; m <= 100; m += 10) {
        final x = xAt(m.toDouble());
        canvas.drawLine(
          Offset(x, top + laneH - 16),
          Offset(x, top + laneH - 6),
          Paint()
            ..color = const Color(0xFF3A4D68)
            ..strokeWidth = 2,
        );
        _text(canvas, '$m', Offset(x, top + laneH - 34), 13, const Color(0xFF6F86A3), center: true);
      }
    }
    // 起跑線與終點線
    canvas.drawLine(Offset(x0, 4), Offset(x0, size.height - 4), Paint()..color = Colors.white54..strokeWidth = 3);
    _finishLine(canvas, xAt(trackMeters), 4, size.height - 4);

    for (final l in engine.lanes) {
      final top = laneH * l.index;
      final base = top + laneH - 40; // 腳底
      _text(canvas, '${l.label} 道', Offset(14, top + laneH * 0.28), 22, laneColor(l.index), bold: true);
      _text(canvas, l.name, Offset(14, top + laneH * 0.28 + 28), 16, Colors.white70);
      if (!l.hasPlayer) continue;
      final x = xAt(l.distance);
      _stickman(canvas, Offset(x, base), math.min(laneH * 0.62, 150), l);
      _text(canvas, '${l.distance.toStringAsFixed(1)} m  ${l.speed.toStringAsFixed(1)} m/s',
          Offset(x, base - math.min(laneH * 0.62, 150) - 18), 14, laneColor(l.index), center: true);
    }
  }

  void _finishLine(Canvas canvas, double x, double y0, double y1) {
    const cell = 10.0;
    final dark = Paint()..color = Colors.black;
    final light = Paint()..color = Colors.white;
    var row = 0;
    for (double y = y0; y < y1; y += cell, row++) {
      final h = math.min(cell, y1 - y);
      canvas.drawRect(Rect.fromLTWH(x - cell, y, cell, h), row.isEven ? light : dark);
      canvas.drawRect(Rect.fromLTWH(x, y, cell, h), row.isEven ? dark : light);
    }
  }

  /// 火柴人：腳底在 foot，高度約 s。跑步擺動幅度隨速度變大。
  void _stickman(Canvas canvas, Offset foot, double s, Lane l) {
    final color = laneColor(l.index);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(3, s * 0.045);
    final amp = (l.speed / 3.0).clamp(0.0, 1.0).toDouble();
    final ph = l.stride;

    Offset pt(Offset o, double len, double ang) => Offset(o.dx + len * math.sin(ang), o.dy + len * math.cos(ang));

    final legLen = s * 0.30;
    final hip = Offset(foot.dx, foot.dy - legLen * 2 * 0.96);
    final lean = 0.22 * amp; // 身體前傾
    final neck = Offset(hip.dx + s * 0.34 * math.sin(lean), hip.dy - s * 0.34 * math.cos(lean));
    final headR = s * 0.11;
    final head = Offset(neck.dx + headR * 1.1 * math.sin(lean), neck.dy - headR * 1.1 * math.cos(lean));

    canvas.drawLine(hip, neck, paint);
    canvas.drawCircle(head, headR, paint);

    // 腿：兩腿相位差 π
    for (final side in [0.0, math.pi]) {
      final a = math.sin(ph + side) * 0.85 * amp; // 大腿前後擺
      final bend = (0.5 + 0.5 * math.cos(ph + side + 0.9)) * 1.1 * amp; // 小腿向後折
      final knee = pt(hip, legLen, a);
      final ankle = pt(knee, legLen, a - bend);
      canvas.drawLine(hip, knee, paint);
      canvas.drawLine(knee, ankle, paint);
    }
    // 手：與腿反向
    final armLen = s * 0.19;
    for (final side in [0.0, math.pi]) {
      final a = -math.sin(ph + side) * 0.9 * amp;
      final elbow = pt(neck, armLen, a);
      final hand = pt(elbow, armLen, a + 0.9 + 0.3 * amp);
      canvas.drawLine(neck, elbow, paint);
      canvas.drawLine(elbow, hand, paint);
    }
    if (l.finishTime != null) {
      _text(canvas, '🏁', Offset(head.dx, head.dy - headR - 22), 20, Colors.white, center: true);
    }
  }

  void _text(Canvas canvas, String t, Offset at, double size, Color c, {bool center = false, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(fontSize: size, color: c, fontWeight: bold ? FontWeight.w900 : FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center ? Offset(at.dx - tp.width / 2, at.dy) : at);
  }

  @override
  bool shouldRepaint(covariant TrackPainter old) => true;
}
