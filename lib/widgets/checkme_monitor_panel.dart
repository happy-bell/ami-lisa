import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/checkme_pro_service.dart';
import 'package:amiapp/services/tv_pi_checkme_share.dart';

/// 46amip4 `checkme_monitor.php` と同じライブモニタ。
class CheckmeMonitorPanel extends StatefulWidget {
  const CheckmeMonitorPanel({super.key});

  @override
  State<CheckmeMonitorPanel> createState() => _CheckmeMonitorPanelState();
}

class _CheckmeMonitorPanelState extends State<CheckmeMonitorPanel> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    CheckmeProService.instance.addListener(_onChanged);
    CheckmeShareView.instance.addListener(_onChanged);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    CheckmeProService.instance.removeListener(_onChanged);
    CheckmeShareView.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final share = CheckmeShareView.instance;
    final pro = CheckmeProService.instance;
    // 自分が測定中なら受信共有よりローカル波形を優先する。
    final useShare =
        AppManager.isPiTvLayout && share.active && !pro.userEnabled;
    final measuring = useShare ? share.recent : pro.measuring;
    final hr = useShare ? share.hr : pro.hr;
    final spo2 = useShare ? share.spo2 : pro.spo2;
    final pr = useShare ? share.pr : pro.pr;
    final pi = useShare ? share.pi : pro.pi;
    final ecg = useShare ? share.ecg : pro.ecg;
    final pleth = useShare ? share.pleth : pro.pleth;
    final waveVersion = useShare ? share.waveVersion : pro.waveVersion;
    final closeRemain = useShare ? 0 : pro.closeRemainSeconds;
    return Opacity(
      opacity: 0.7,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: ColoredBox(
          color: Colors.black,
          child: Column(
            children: [
              _header(measuring, closeRemain),
              Expanded(
                child: _body(
                  measuring: measuring,
                  hr: hr,
                  spo2: spo2,
                  pr: pr,
                  pi: pi,
                  ecg: ecg,
                  pleth: pleth,
                  waveVersion: waveVersion,
                  stretchToWidth: useShare,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(bool measuring, int closeRemain) {
    final state = measuring ? '受信中' : '受信 -- ($closeRemain)';
    return Container(
      height: 34,
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerRight,
      child: Text(
        state,
        style: const TextStyle(
          color: Color(0xFF9AA6AD),
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _body({
    required bool measuring,
    required int? hr,
    required int? spo2,
    required int? pr,
    required double? pi,
    required List<int> ecg,
    required List<int> pleth,
    required int waveVersion,
    required bool stretchToWidth,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideW =
            (constraints.maxWidth * 0.11).clamp(60.0, 95.0);
        final cqw = constraints.maxWidth / 100.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomPaint(
                painter: _CheckmeWavePainter(
                  ecg: ecg,
                  pleth: pleth,
                  version: waveVersion,
                  stretchToWidth: stretchToWidth,
                ),
              ),
            ),
            Container(
              width: sideW,
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Color(0xFF1E9DFA), width: 2),
                ),
              ),
              child: Column(
                children: [
                  _cell(
                    label: 'HR/min',
                    value: _num(hr),
                    color: const Color(0xFF22E022),
                    valueCqw: 7.0,
                    labelCqw: 2.8,
                    cqw: cqw,
                    idle: !measuring,
                  ),
                  _cell(
                    label: '%SpO2',
                    value: _num(spo2),
                    color: const Color(0xFF1E9DFA),
                    valueCqw: 6.65,
                    labelCqw: 2.8,
                    cqw: cqw,
                    idle: !measuring,
                  ),
                  _cell(
                    label: 'PR',
                    sub: '/min',
                    value: _num(pr),
                    color: const Color(0xFF1E9DFA),
                    valueCqw: 5.85,
                    labelCqw: 2.4,
                    cqw: cqw,
                    idle: !measuring,
                  ),
                  _cell(
                    label: 'PI',
                    value: _pi(pi),
                    color: const Color(0xFF1E9DFA),
                    valueCqw: 5.85,
                    labelCqw: 2.4,
                    cqw: cqw,
                    idle: !measuring,
                    last: true,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _cell({
    required String label,
    String? sub,
    required String value,
    required Color color,
    required double valueCqw,
    required double labelCqw,
    required double cqw,
    required bool idle,
    bool last = false,
  }) {
    return Expanded(
      child: Container(
        decoration: last
            ? null
            : const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFF1E9DFA), width: 2),
                ),
              ),
        child: Opacity(
          opacity: idle ? 0.45 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: labelCqw * cqw,
                    height: 1.05,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: color,
                      fontSize: valueCqw * cqw,
                      fontWeight: FontWeight.w700,
                      height: 1.05,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (sub != null)
                  Text(
                    sub,
                    maxLines: 1,
                    style: TextStyle(
                      color: color,
                      fontSize: 2 * cqw,
                      height: 1.05,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _num(int? v) {
    if (v == null || v == 0) return '--';
    return '$v';
  }

  String _pi(double? v) {
    if (v == null || v == 0) return '--';
    return v.toStringAsFixed(1);
  }
}

class _CheckmeWavePainter extends CustomPainter {
  _CheckmeWavePainter({
    required this.ecg,
    required this.pleth,
    required this.version,
    this.stretchToWidth = false,
  });

  static const _bg = Color(0xFF000000);
  static const _gridFine = Color(0xFF262E29);
  static const _gridMed = Color(0xFF3C473F);
  static const _gridMajor = Color(0xFF78867C);
  static const _ecg = Color(0xFF22E022);
  static const _pleth = Color(0xFF37B6F0);
  static const _majorSquares = 5.0;
  static const _smallPerMajor = 25.0;
  static const _cellsAcross = _majorSquares * _smallPerMajor;
  static const _fs = 125.0;
  static const _secPerSmall = 0.04; // 大マス 0.2秒
  static const _samplesPerSmall = _fs * _secPerSmall; // 5

  final List<int> ecg;
  final List<int> pleth;
  final int version;
  final bool stretchToWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w < 2 || h < 2) return;

    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);
    final mm = w / _cellsAcross;
    _drawGrid(canvas, w, h, mm);

    final sy = h * 0.5;
    final visible = math.max(4, (w / mm * _samplesPerSmall).floor());
    // 30%間引き後も格子幅いっぱいになるよう、Piは 10/7 倍取ってから間引く。
    final take = AppManager.isPiTvLayout
        ? math.max(visible, (visible * 10 / 7).ceil())
        : visible;
    _plotEcg(canvas, ecg, 0, sy, w, mm, take);
    _plotPleth(canvas, pleth, sy, h, w, mm, take);
  }

  void _drawGrid(Canvas canvas, double w, double h, double mm) {
    for (final pass in [0, 1, 2]) {
      for (var i = 0; i * mm <= w; i++) {
        final major = i % 25 == 0;
        final med = i % 5 == 0;
        if (pass == 0 && (med || major)) continue;
        if (pass == 1 && (!med || major)) continue;
        if (pass == 2 && !major) continue;
        final paint = _gridPaint(i);
        final x = (i * mm).roundToDouble() + 0.5;
        canvas.drawLine(Offset(x, 0), Offset(x, h), paint);
      }
      for (var j = 0; j * mm <= h; j++) {
        final major = j % 25 == 0;
        final med = j % 5 == 0;
        if (pass == 0 && (med || major)) continue;
        if (pass == 1 && (!med || major)) continue;
        if (pass == 2 && !major) continue;
        final paint = _gridPaint(j);
        final y = (j * mm).roundToDouble() + 0.5;
        canvas.drawLine(Offset(0, y), Offset(w, y), paint);
      }
    }
  }

  Paint _gridPaint(int i) {
    if (i % 25 == 0) {
      return Paint()
        ..color = _gridMajor
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke;
    }
    if (i % 5 == 0) {
      return Paint()
        ..color = _gridMed
        ..strokeWidth = 0.9
        ..style = PaintingStyle.stroke;
    }
    return Paint()
      ..color = _gridFine
      ..strokeWidth = 0.4
      ..style = PaintingStyle.stroke;
  }

  void _plotEcg(
    Canvas canvas,
    List<int> data,
    double top,
    double bottom,
    double w,
    double mm,
    int visible,
  ) {
    final samples = _prepare(data, stretchToWidth ? math.min(data.length, (5 * _fs).round()) : visible);
    if (samples.length < 4) return;
    final baseline = _median(samples);
    var peak = 0.0;
    final absDev = <double>[];
    for (final v in samples) {
      absDev.add((v - baseline).abs());
    }
    absDev.sort();
    peak = absDev[(absDev.length * 0.98).floor().clamp(0, absDev.length - 1)];
    // 1.0mV = 大マス2つ（小マス10）。R波がだいたいこの高さになる。
    final targetPx = 10.0 * mm;
    final gain = peak < 20 ? targetPx / 2000.0 : targetPx / peak;
    final mid = (top + bottom) / 2;
    // 共有波形は 46amip4 checkme_monitor.php と同じく横幅いっぱいに伸ばす。
    final stepX = stretchToWidth && samples.length > 1
        ? w / (samples.length - 1)
        : mm / _samplesPerSmall;
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = i * stepX;
      var y = mid - (samples[i] - baseline) * gain;
      if (y < top) y = top;
      if (y > bottom) y = bottom;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      _wavePaint(_ecg, w, sharp: !AppManager.isPiTvLayout),
    );
  }

  void _plotPleth(
    Canvas canvas,
    List<int> data,
    double top,
    double bottom,
    double w,
    double mm,
    int visible,
  ) {
    final samples = _prepare(data, stretchToWidth ? math.min(data.length, (5 * _fs).round()) : visible);
    if (samples.length < 4) return;
    var lo = samples.first;
    var hi = samples.first;
    for (final v in samples) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final span = math.max(1.0, (hi - lo).toDouble());
    final band = bottom - top;
    final pad = band * 0.18;
    final stepX = stretchToWidth && samples.length > 1
        ? w / (samples.length - 1)
        : mm / _samplesPerSmall;
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = i * stepX;
      final y = bottom - pad - ((samples[i] - lo) / span) * (band - pad * 2);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, _wavePaint(_pleth, w, sharp: false));
  }

  Paint _wavePaint(Color color, double w, {required bool sharp}) {
    return Paint()
      ..color = color
      ..strokeWidth = math.max(1.4, 2.2 * (w / 1400))
      ..style = PaintingStyle.stroke
      ..strokeJoin = sharp ? StrokeJoin.miter : StrokeJoin.round
      ..strokeCap = sharp ? StrokeCap.butt : StrokeCap.round
      ..strokeMiterLimit = 8
      ..isAntiAlias = true;
  }

  List<double> _prepare(List<int> data, int visible) {
    if (data.length < 4) return const [];
    final start = math.max(0, data.length - visible);
    final out = <double>[];
    var prev = 0.0;
    var have = false;
    for (var i = start; i < data.length; i++) {
      var v = data[i].toDouble();
      if (v.abs() >= 32000) {
        v = have ? prev : 0;
      } else if (have) {
        var d = v - prev;
        while (d > 32767) {
          d -= 65536;
        }
        while (d < -32768) {
          d += 65536;
        }
        v = prev + d;
      }
      out.add(v);
      prev = v;
      have = true;
    }
    return _thinDisplay(out);
  }

  /// ラズパイ版の表示だけ 30% 間引き（10点中7点残す）。TCLは変えない。
  List<double> _thinDisplay(List<double> data) {
    if (!AppManager.isPiTvLayout) return data;
    if (data.length < 8) return data;
    final out = <double>[];
    for (var i = 0; i < data.length; i++) {
      if (i % 10 < 7) out.add(data[i]);
    }
    return out;
  }

  double _median(List<double> data) {
    final s = List<double>.from(data)..sort();
    final n = s.length;
    if (n == 0) return 0;
    if (n.isOdd) return s[n >> 1];
    return (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
  }

  @override
  bool shouldRepaint(covariant _CheckmeWavePainter oldDelegate) {
    return oldDelegate.version != version ||
        oldDelegate.stretchToWidth != stretchToWidth;
  }
}
