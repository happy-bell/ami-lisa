import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/services/tv_health_notify.dart';
import 'package:amiapp/widgets/tv_focusable.dart';
import 'package:flutter/material.dart';

/// ラズパイ版の健康管理。TCLアミ／スタッフからは開かない。
class TvHealthPage extends StatefulWidget {
  const TvHealthPage({super.key});

  @override
  State<TvHealthPage> createState() => _TvHealthPageState();
}

class _TvHealthPageState extends State<TvHealthPage> {
  TvHealthState _state = TvHealthState();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final state = await TvHealthNotify.instance.fetch();
    if (!mounted) return;
    setState(() {
      _state = state;
      _loading = false;
    });
  }

  Future<void> _send(String type, String time, String value) async {
    await TvHealthNotify.instance.send(type, time, value);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: WidgetUtil.appBar(
        '健康管理・お薬管理',
        backgroundColor: WidgetUtil.iosNavbarBG,
        foregroundColor: Colors.black,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TvHealthQuestions(
              state: _state,
              onSend: _send,
            ),
    );
  }
}

/// ラズパイ版ホームの指定時刻オーバーレイと、健康管理ページで共用する。
class TvHealthQuestions extends StatelessWidget {
  const TvHealthQuestions({
    super.key,
    required this.state,
    required this.onSend,
    this.compact = false,
  });

  final TvHealthState state;
  final Future<void> Function(String type, String time, String value) onSend;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final titleSize = compact ? 24.0 : 28.0;
    return ListView(
      padding: EdgeInsets.all(compact ? 16 : 24),
      children: [
        if (state.showMedical) ...[
          Text('お薬を飲みましたか？',
              style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _action('飲んだ', () {
            onSend('medical', '${state.medicalTime}', '1');
          }, autofocus: true),
          const SizedBox(height: 28),
        ],
        if (state.showHealth) ...[
          Text('体調はいかがですか？',
              style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _action('良い', () {
                  onSend('health', '${state.healthTime}', '1');
                }),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _action('普通', () {
                  onSend('health', '${state.healthTime}', '2');
                }),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _action('悪い', () {
                  onSend('health', '${state.healthTime}', '3');
                }),
              ),
            ],
          ),
          const SizedBox(height: 28),
        ],
        if (state.showDayService) ...[
          Text(
            '今日のデイサービスの時間は${state.dayServiceText}',
            style: TextStyle(fontSize: compact ? 22 : 26, fontWeight: FontWeight.bold),
          ),
          if (state.showDayServiceCheck) ...[
            const SizedBox(height: 12),
            _action('確認した', () {
              onSend('dayservice', '${state.dayServiceTime}', '1');
            }),
          ],
          const SizedBox(height: 28),
        ],
        if (!state.hasAny)
          const Text(
            'いま表示するお知らせはありません',
            style: TextStyle(fontSize: 22),
          ),
      ],
    );
  }

  Widget _action(String label, VoidCallback onPressed, {bool autofocus = false}) {
    return TvFocusable(
      autofocus: TvUtil.isTelevision && autofocus,
      onPressed: onPressed,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF5CB85C),
          foregroundColor: Colors.white,
          minimumSize: const Size(120, 56),
          textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        child: Text(label),
      ),
    );
  }
}
