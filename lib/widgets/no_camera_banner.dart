import 'package:flutter/material.dart';

/// カメラ未接続のとき、設定の直下に出す赤バナー。
class NoCameraBanner extends StatelessWidget {
  const NoCameraBanner({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final padV = compact ? 8.0 : 12.0;
    final font = compact ? 16.0 : 22.0;
    return SizedBox(
      height: padV * 2 + font * 1.1 - 5,
      child: ColoredBox(
        color: const Color(0xFFCC0000),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              'NO CAMERA',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: font,
                height: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
