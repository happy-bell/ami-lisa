import 'package:amiapp/services/and_vital_service.dart';
import 'package:flutter/material.dart';

/// Ring の SpO2 ポップアップと同じ場所・同じ見た目。
class AndVitalResultPopup extends StatelessWidget {
  const AndVitalResultPopup({super.key});

  @override
  Widget build(BuildContext context) {
    final and = AndVitalService.instance;
    const labelSize = 20.0 * 0.8;
    const numSize = 36.0 * 0.85;

    Widget row(
      String label,
      String value, {
      double labelScale = 1,
      double numScale = 1,
    }) {
      return Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: labelSize * labelScale,
                color: const Color(0xFF111111),
                height: 1.2,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: numSize * numScale,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF111111),
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final rows = <Widget>[];
    switch (and.lastKind) {
      case AndVitalKind.blood:
        rows.addAll([
          row(
            '最高血圧',
            and.systolic?.toString() ?? '-',
            labelScale: 0.9,
            numScale: 0.75,
          ),
          row(
            '最低血圧',
            and.diastolic?.toString() ?? '-',
            labelScale: 0.9,
            numScale: 0.75,
          ),
          row(
            '脈拍',
            and.pulse?.toString() ?? '-',
            labelScale: 0.9,
            numScale: 0.75,
          ),
        ]);
        break;
      case AndVitalKind.temp:
        rows.add(row('体温', and.temperature?.toStringAsFixed(1) ?? '-'));
        break;
      case AndVitalKind.weight:
        rows.add(row('体重', and.weightKg?.toStringAsFixed(1) ?? '-'));
        break;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 16, 0),
      decoration: BoxDecoration(
        color: const Color(0xFFD9D9D9),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 16, spreadRadius: 2),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
  }
}
