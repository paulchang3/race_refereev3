import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'engine.dart';
import 'host_server.dart';

const Color kLaneA = Color(0xFF22D3EE);
const Color kLaneB = Color(0xFFFB923C);
const Color kPanel = Color(0xFF111C30);
const Color kLine = Color(0xFF1F2F46);

Color laneColor(int i) => i == 0 ? kLaneA : kLaneB;

class LobbyView extends StatelessWidget {
  const LobbyView({super.key, required this.engine, required this.server});

  final RaceEngine engine;
  final HostServer server;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 900;
          final lanes = [
            for (final l in engine.lanes) LanePanel(engine: engine, lane: l),
          ];
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context),
                const SizedBox(height: 12),
                wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 300, child: _joinPanel(context)),
                          const SizedBox(width: 12),
                          Expanded(child: lanes[0]),
                          const SizedBox(width: 12),
                          Expanded(child: lanes[1]),
                        ],
                      )
                    : Column(children: [
                        _joinPanel(context),
                        const SizedBox(height: 12),
                        lanes[0],
                        const SizedBox(height: 12),
                        lanes[1],
                      ]),
                const SizedBox(height: 16),
                _startBar(context),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(children: [
      const Text('🏁 百米賽跑・裁判台',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
      const Spacer(),
      Text('${server.players.values.where((p) => p.connected).length} 人在線',
          style: const TextStyle(fontSize: 16, color: Color(0xFF8AA0B8))),
    ]);
  }

  Widget _joinPanel(BuildContext context) {
    final url = server.url;
    return _Box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (server.error != null)
          Text(server.error!, style: const TextStyle(color: Color(0xFFFCA5A5)))
        else if (url.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('找不到區網 IP：請連上 Wi-Fi 或開啟行動熱點'),
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: QrImageView(data: url, size: 220, backgroundColor: Colors.white),
          ),
          const SizedBox(height: 8),
          SelectableText(url, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
          if (server.addresses.length > 1)
            TextButton(
              onPressed: server.nextAddress,
              child: Text('換一個網址（${server.addressIndex + 1}/${server.addresses.length}）'),
            ),
          const SizedBox(height: 4),
          const Text(
            '手機連同一個 Wi-Fi（或連這支手機的熱點）→ 掃 QR。\n'
            '出現「不安全」警告時，選「進階 → 繼續前往」。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF8AA0B8), height: 1.5),
          ),
        ],
        const Divider(height: 24, color: kLine),
        _playerList(),
      ]),
    );
  }

  Widget _playerList() {
    if (server.players.isEmpty) {
      return const Text('還沒有人加入', style: TextStyle(color: Color(0xFF8AA0B8)));
    }
    return Column(children: [
      for (final p in server.players.values)
        Builder(builder: (context) {
          final lane = engine.laneOf(p.id);
          final tag = lane < 0 ? '觀戰' : engine.lanes[lane].label;
          final color = lane < 0 ? const Color(0xFF8AA0B8) : laneColor(lane);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Icon(Icons.circle, size: 10, color: p.connected ? const Color(0xFF4ADE80) : Colors.grey),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(6)),
                child: Text(tag, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis)),
              IconButton(
                tooltip: '移除',
                visualDensity: VisualDensity.compact,
                onPressed: () => server.kick(p.id),
                icon: const Icon(Icons.close, size: 18),
              ),
            ]),
          );
        }),
    ]);
  }

  Widget _startBar(BuildContext context) {
    final ready = engine.canStart;
    final waiting = engine.lanes.where((l) => !l.hasPlayer || !l.connected).length;
    return Row(children: [
      OutlinedButton.icon(
        onPressed: engine.swapLanes,
        icon: const Icon(Icons.swap_horiz),
        label: const Text('交換跑道'),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: FilledButton(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 20),
            textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          onPressed: ready ? engine.start : null,
          child: Text(ready ? '開始比賽（倒數 3 秒）' : '還需要 $waiting 位選手連線'),
        ),
      ),
    ]);
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kPanel,
          border: Border.all(color: kLine),
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );
}

/// 一條跑道的「賽前靈敏度」面板：原始訊號圖、死區線、轉換後速度。
class LanePanel extends StatelessWidget {
  const LanePanel({super.key, required this.engine, required this.lane});

  final RaceEngine engine;
  final Lane lane;

  @override
  Widget build(BuildContext context) {
    final color = laneColor(lane.index);
    final calibrating = lane.calibRemain > 0;
    final status = !lane.hasPlayer
        ? '等待選手…'
        : lane.connected
            ? lane.name
            : '${lane.name}（斷線）';
    return _Box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${lane.label} 道', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(width: 10),
          Expanded(child: Text(status, style: const TextStyle(fontSize: 20), overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 130,
          width: double.infinity,
          child: CustomPaint(
            painter: SignalChartPainter(
              gyro: lane.gyroHist,
              shake: lane.shakeHist,
              deadzone: lane.deadzone,
              showGyro: lane.source != SignalSource.shake,
              showShake: lane.source != SignalSource.gyro,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 14, runSpacing: 2, children: [
          _legend(kLaneA, '陀螺儀 ${lane.gyro.toStringAsFixed(0)} °/s（峰值 ${lane.gyroPeak.toStringAsFixed(0)}，滿格 ${gyroFullScale.toStringAsFixed(0)}）'),
          _legend(kLaneB, '震動 ${lane.shake.toStringAsFixed(1)} m/s²（峰值 ${lane.shakePeak.toStringAsFixed(1)}，滿格 ${shakeFullScale.toStringAsFixed(0)}）'),
        ]),
        const SizedBox(height: 10),
        SegmentedButton<SignalSource>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: SignalSource.gyro, label: Text('陀螺儀')),
            ButtonSegment(value: SignalSource.shake, label: Text('震動')),
            ButtonSegment(value: SignalSource.both, label: Text('兩者取大')),
          ],
          selected: {lane.source},
          onSelectionChanged: (s) {
            lane.source = s.first;
            engine.touch();
          },
        ),
        _slider('靈敏度 ×${lane.gain.toStringAsFixed(2)}', lane.gain, 0.3, 3.0, (v) {
          lane.gain = v;
          engine.touch();
        }),
        _slider('死區 ${(lane.deadzone * 100).toStringAsFixed(0)}%（低於白線不算）', lane.deadzone, 0, 0.6, (v) {
          lane.deadzone = v;
          engine.touch();
        }),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                minHeight: 14,
                value: (lane.speed / hardCapSpeed).clamp(0.0, 1.0).toDouble(),
                color: color,
                backgroundColor: const Color(0xFF16233A),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
            child: Text('${lane.speed.toStringAsFixed(1)} m/s',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ]),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: lane.hasPlayer && !calibrating ? () => engine.startCalibration(lane) : null,
            icon: const Icon(Icons.tune),
            label: Text(calibrating ? '校準中…請把手機放著不動' : '靜止校準（2 秒，自動設死區）'),
          ),
        ),
      ]),
    );
  }

  Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 4, color: c),
        const SizedBox(width: 6),
        Flexible(child: Text(t, style: const TextStyle(fontSize: 12, color: Color(0xFFB6C4D6)))),
      ]);

  Widget _slider(String label, double v, double min, double max, ValueChanged<double> on) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(label, style: const TextStyle(fontSize: 14)),
        ),
        Slider(value: v.clamp(min, max).toDouble(), min: min, max: max, onChanged: on),
      ]);
}

class SignalChartPainter extends CustomPainter {
  SignalChartPainter({
    required this.gyro,
    required this.shake,
    required this.deadzone,
    required this.showGyro,
    required this.showShake,
  });

  final List<double> gyro, shake;
  final double deadzone;
  final bool showGyro, showShake;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8));
    canvas.drawRRect(bg, Paint()..color = const Color(0xFF0B1220));
    canvas.save();
    canvas.clipRRect(bg);

    final grid = Paint()
      ..color = const Color(0xFF1F2F46)
      ..strokeWidth = 1;
    for (final f in [0.25, 0.5, 0.75]) {
      final y = size.height * (1 - f);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    if (showShake) _line(canvas, size, shake, kLaneB);
    if (showGyro) _line(canvas, size, gyro, kLaneA);

    // 死區（白色虛線）
    final dz = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5;
    final y = size.height * (1 - deadzone);
    for (double x = 0; x < size.width; x += 12) {
      canvas.drawLine(Offset(x, y), Offset(x + 6, y), dz);
    }
    canvas.restore();
  }

  void _line(Canvas canvas, Size size, List<double> d, Color c) {
    if (d.length < 2) return;
    final path = Path();
    for (var i = 0; i < d.length; i++) {
      final x = size.width * (i + (histLen - d.length)) / (histLen - 1);
      final y = size.height * (1 - d[i].clamp(0.0, 1.0));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant SignalChartPainter old) => true;
}
