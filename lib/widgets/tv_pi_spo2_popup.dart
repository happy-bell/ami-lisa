import 'package:flutter/material.dart';

/// ラズパイ版 SpO2 ポップアップ（TCLアミと同じ数値レイアウト）。
class TvPiSpo2Popup extends StatelessWidget {
  const TvPiSpo2Popup({
    super.key,
    required this.spo2,
    required this.pr,
  });

  final String spo2;
  final String pr;

  static const double boxWidth = 280 * 0.6;
  static const double messageGap = 20;
  static const double tvMessageHeight = 62;

  static double rightInset(double sidebarWidth) => sidebarWidth + 24;

  static double bottomInset({double messageHeight = tvMessageHeight}) =>
      messageHeight + messageGap;

  @override
  Widget build(BuildContext context) {
    const labelSize = 16.0;
    const numSize = 24.0;

    Widget row(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(top: 1, bottom: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: labelSize,
                color: Color(0xFF111111),
                height: 1.2,
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: numSize,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111111),
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: boxWidth,
      padding: const EdgeInsets.fromLTRB(7, 5, 10, 5),
      decoration: BoxDecoration(
        color: const Color(0xFFD9D9D9),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 16, spreadRadius: 2),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row('SpO2(%)', spo2),
          row('PRbpm', pr),
        ],
      ),
    );
  }
}
