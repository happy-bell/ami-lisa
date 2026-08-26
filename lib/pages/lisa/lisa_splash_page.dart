import 'dart:async';

import 'package:flutter/material.dart';

import 'package:amiapp/pages/lisa/lisa_terms_page.dart';
import 'package:amiapp/widgets/lisa_logo.dart';

/// LiSA の起動画面。ロゴを浮かび上がらせ、光を流してから静かに消す。
///
/// 高齢の利用者が見るため、動きは控えめにしている。
/// 派手なスライドや回転は落ち着かず、目にも負担になる。
///
/// [onFinished] を渡すと、画面遷移せずに呼び出し元へ制御を返す。
/// 毎回の起動で出すため、次に何を出すかは呼び出し元が決める。
class LisaSplashPage extends StatefulWidget {
  const LisaSplashPage({super.key, this.onFinished});

  final VoidCallback? onFinished;

  @override
  State<LisaSplashPage> createState() => _LisaSplashPageState();
}

class _LisaSplashPageState extends State<LisaSplashPage>
    with TickerProviderStateMixin {
  /// 表示から消え終わるまでの全体時間。
  static const _total = Duration(seconds: 5);

  late final AnimationController _controller;

  late final Animation<double> _fade;   // 全体の明るさ
  late final Animation<double> _scale;  // わずかな拡大
  late final Animation<double> _shine;  // 光の位置（-0.4 → 1.4）

  Timer? _next;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: _total);

    // 5秒の内訳。
    //   0.00-0.36 (1.8秒) ロゴがゆっくり現れる
    //   0.30-0.76 (2.3秒) 光が左から右へ流れる
    //   0.76-0.92 (0.8秒) ロゴが消える
    //   0.92-1.00 (0.4秒) 何もない黒。余韻を置いてから次へ
    _fade = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 36,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 40),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(
          CurveTween(curve: Curves.easeIn),
        ),
        weight: 16,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 8),
    ]).animate(_controller);

    // ごくわずかに大きくなるだけ。静かに近づいてくる印象にする。
    _scale = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
      ),
    );

    // 光の帯。画面の外から入って外へ抜ける。
    _shine = Tween<double>(begin: -0.4, end: 1.4).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.30, 0.76, curve: Curves.easeInOut),
      ),
    );

    _controller.forward();
    _next = Timer(_total, _goNext);
  }

  @override
  void dispose() {
    _next?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _goNext() {
    if (!mounted) return;
    final done = widget.onFinished;
    if (done != null) {
      done();
      return;
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LisaTermsPage(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Opacity(
            opacity: _fade.value,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _shineLayer(),
                Center(
                  child: Transform.scale(
                    scale: _scale.value,
                    child: const LisaLogo(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 背後を左から右へ流れる光。
  ///
  /// 画面いっぱいに広げ、帯そのものは画面の倍の大きさで作る。
  /// 小さい枠に収めると回したときに角が見え、光ではなく板が
  /// 横切っているように見えてしまう。
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
