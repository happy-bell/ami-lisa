import 'package:flutter/material.dart';

/// LiSA のロゴ。起動画面と、前面に戻ったときの重ね表示で共用する。
///
/// 画像が用意できない環境でも起動できるよう、文字で組んだ控えを持たせている。
class LisaLogo extends StatelessWidget {
  const LisaLogo({super.key, this.width = 520});

  final double width;

  static const _blue = Color(0xFF2E9BE0);
  static const _orange = Color(0xFFF08A24);

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/lisa_logo.png',
      width: width,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _fallback(),
    );
  }

  Widget _fallback() {
    final scale = width / 520;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'ami',
              style: TextStyle(
                fontSize: 64 * scale,
                fontWeight: FontWeight.bold,
                color: _blue,
                letterSpacing: -1,
              ),
            ),
            SizedBox(width: 22 * scale),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'Li',
                    style: TextStyle(
                      fontSize: 96 * scale,
                      fontWeight: FontWeight.bold,
                      color: _blue,
                    ),
                  ),
                  TextSpan(
                    text: 'S',
                    style: TextStyle(
                      fontSize: 96 * scale,
                      fontWeight: FontWeight.bold,
                      color: _orange,
                    ),
                  ),
                  TextSpan(
                    text: 'A',
                    style: TextStyle(
                      fontSize: 96 * scale,
                      fontWeight: FontWeight.bold,
                      color: _blue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 6 * scale),
        Text(
          'テレビ電話amiシリーズ',
          style: TextStyle(
            fontSize: 22 * scale,
            color: _blue,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}
