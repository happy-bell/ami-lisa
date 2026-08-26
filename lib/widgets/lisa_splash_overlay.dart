import 'package:flutter/material.dart';

import 'package:amiapp/widgets/lisa_logo.dart';

/// 前面に戻ったときに、いまの画面の上へロゴを重ねて出す。
///
/// 起動時のスプラッシュ（[LisaSplashPage]）と違い、**画面を差し替えない**。
/// 差し替えると居室画面が作り直され、着信の受け口ごと壊れてしまう。
/// ここは上に乗せるだけなので、裏では通話も着信もそのまま動き続ける。
///
/// 使い方: `LisaSplashOverlay.show()` を呼ぶと2秒だけ流れる。
class LisaSplashOverlay extends StatefulWidget {
  const LisaSplashOverlay({super.key});

  /// 表示のきっかけ。数を増やすと重ね表示が始まる。
  static final ValueNotifier<int> _trigger = ValueNotifier<int>(0);

  /// ロゴを重ねて出す。表示中に呼ばれた場合は何もしない。
  static void show() => _trigger.value++;

  @override
  State<LisaSplashOverlay> createState() => _LisaSplashOverlayState();
}

class _LisaSplashOverlayState extends State<LisaSplashOverlay>
    with SingleTickerProviderStateMixin {
  /// 出てから消えるまで。起動時より短くする。
  /// 戻ってくるたびに長く待たされると煩わしい。
  static const _total = Duration(seconds: 2);

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _shine;

  int _lastTrigger = 0;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _total);

    // 2秒の内訳。
    //   0.0-0.4秒 現れる
    //   0.3-1.4秒 光が左から右へ流れる
    //   1.4-2.0秒 消える
    _fade = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 30,
      ),
    ]).animate(_controller);

    _shine = Tween<double>(begin: -0.4, end: 1.4).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.15, 0.70, curve: Curves.easeInOut),
      ),
    );

    _lastTrigger = LisaSplashOverlay._trigger.value;
    LisaSplashOverlay._trigger.addListener(_onTrigger);
  }

  @override
  void dispose() {
    LisaSplashOverlay._trigger.removeListener(_onTrigger);
    _controller.dispose();
    super.dispose();
  }

  void _onTrigger() {
    final v = LisaSplashOverlay._trigger.value;
    if (v == _lastTrigger) return;
    _lastTrigger = v;
    if (_visible) return;   // 出ている最中は重ねない

    setState(() => _visible = true);
    _controller.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    // 操作を邪魔しない。裏の画面がそのままキーを受け取れるようにする。
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Opacity(
            opacity: _fade.value,
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _shineLayer(),
                  const Center(child: LisaLogo()),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 背後を左から右へ流れる光。起動画面と同じ見え方に揃えている。
  Widget _shineLayer() {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          return OverflowBox(
            maxWidth: w * 2,
            maxHeight: h * 2,
            child: Transform.translate(
              offset: Offset(_shine.value * w * 1.5, 0),
              child: Transform.rotate(
                angle: -0.30,
                child: SizedBox(
                  width: w * 2,
                  height: h * 2,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0x00FFFFFF),
                          Color(0x00FFFFFF),
                          Color(0x0AFFFFFF),
                          Color(0x2EFFFFFF),
                          Color(0x0AFFFFFF),
                          Color(0x00FFFFFF),
                          Color(0x00FFFFFF),
                        ],
                        stops: [0.0, 0.42, 0.47, 0.5, 0.53, 0.58, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
