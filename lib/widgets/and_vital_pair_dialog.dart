import 'package:amiapp/services/and_vital_service.dart';
import 'package:amiapp/widgets/tv_focusable.dart';
import 'package:flutter/material.dart';

/// x-amibl789/ami_blepair.py と同じ流れ（開始 / 初期化 / 戻る）。
class AndVitalPairDialog extends StatefulWidget {
  const AndVitalPairDialog({super.key});

  @override
  State<AndVitalPairDialog> createState() => _AndVitalPairDialogState();
}

class _AndVitalPairDialogState extends State<AndVitalPairDialog> {
  String _status = '';
  bool _busy = false;

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '測定器をペアリングモードにしてください';
    });
    final results = await AndVitalService.instance.pairDevices(
      log: (m) {
        if (!mounted) return;
        setState(() => _status = m);
      },
    );
    if (!mounted) return;
    final ok = results.values.where((v) => v).length;
    final total = results.length;
    final msg = total == 0
        ? '測定器が見つかりませんでした End'
        : 'ペアリング完了: $ok/$total 台成功 End';
    setState(() {
      _status = msg;
      _busy = false;
    });
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _clear() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '初期化中です。しばらくお待ちください';
    });
    await AndVitalService.instance.clearPairing(
      log: (m) {
        if (!mounted) return;
        setState(() => _status = m);
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF222222),
      title: const Text(
        '測定器ペアリング',
        style: TextStyle(color: Colors.white, fontSize: 22),
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '測定器をペアリングモードにしてください',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              '画面に End が出るまで操作しないようにしてください',
              style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 16),
            ),
            const SizedBox(height: 16),
            Text(
              _status,
              style: const TextStyle(color: Color(0xFF88DDFF), fontSize: 18),
            ),
          ],
        ),
      ),
      actions: [
        TvDialogAction(
          autofocus: true,
          label: '開始',
          onPressed: _busy ? () {} : _start,
        ),
        TvDialogAction(
          label: '初期化',
          onPressed: _busy ? () {} : _clear,
        ),
        TvDialogAction(
          label: '戻る',
          onPressed: _busy ? () {} : () => Navigator.pop(context),
        ),
      ],
    );
  }
}
