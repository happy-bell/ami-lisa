import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/services/tv_health_notify.dart';
import 'package:amiapp/widgets/tv_pi_focus_button.dart';
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
      body: SafeArea(
        child: _loading
            ? Stack(
                children: [
                  const Center(child: CircularProgressIndicator()),
                  Positioned(
                    top: 8,
                    right: 16,
                    child: SizedBox(
                      width: 160,
                      height: 48,
                      child: TvPiFocusButton(
                        label: '戻る',
                        onPressed: () => Navigator.of(context).pop(),
                        color: const Color(0xFF666666),
                        autofocus: TvUtil.isTelevision,
                        padding: EdgeInsets.zero,
                        fontSize: 24 * 1.2,
                      ),
                    ),
                  ),
                ],
              )
            : TvHealthQuestions(
                state: _state,
                title: '健康管理・お薬管理・デイサービス',
                onBack: () => Navigator.of(context).pop(),
                onSend: _send,
              ),
      ),
    );
  }
}

/// ラズパイ版ホームの指定時刻オーバーレイと、健康管理ページで共用する。
class TvHealthQuestions extends StatefulWidget {
  const TvHealthQuestions({
    super.key,
    required this.state,
    required this.onSend,
    this.compact = false,
    this.onBack,
    this.title,
  });

  final TvHealthState state;
  final Future<void> Function(String type, String time, String value) onSend;
  final bool compact;
  final VoidCallback? onBack;
  final String? title;

  @override
  State<TvHealthQuestions> createState() => _TvHealthQuestionsState();
}

class _TvHealthQuestionsState extends State<TvHealthQuestions> {
  /// 文字はこれまでの拡大を維持。枠は文字が入る高さに固定して空ボタンを防ぐ。
  static const double _actionFont = 26 * 0.8 * 1.2 * 1.15;
  static const double _actionHeight = 56;
  static const double _backFont = 24 * 1.2;
  static const double _backHeight = 48;

  final FocusNode _backFocus = FocusNode(debugLabel: 'health_back');
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'health_scope');

  @override
  void initState() {
    super.initState();
    if (widget.onBack != null && TvUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scope.requestFocus();
        _backFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _backFocus.dispose();
    _scope.dispose();
    super.dispose();
  }

  Future<void> _press(String type, String time, String value) async {
    await widget.onSend(type, time, value);
    if (!mounted) return;
    // 送信後もフォーカスが裏メニューへ逃げないようにする
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.onBack != null && _backFocus.canRequestFocus) {
        _backFocus.requestFocus();
      } else {
        _scope.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final titleSize = widget.compact ? 36.0 : 32.0;
    final headingSize = (widget.compact ? 32.0 : 28.0) * 1.1 * 1.1;
    final daySize = (widget.compact ? 30.0 : 26.0) * 1.1 * 1.05;

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.title != null) ...[
          Padding(
            // タイトルだけ上へ 20px（他は動かさない）
            padding: const EdgeInsets.only(top: 0, bottom: 28),
            child: Transform.translate(
              offset: const Offset(0, -20),
              child: Text(
                widget.title!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: headingSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
        if (widget.state.showMedical) ...[
          Text(
            'お薬を飲みましたか？',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _action(
                  '飲んだ',
                  () => _press('medical', '${widget.state.medicalTime}', '1'),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _action(
                  '飲まない',
                  () => _press('medical', '${widget.state.medicalTime}', '2'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (widget.state.showHealth) ...[
          Text(
            '体調はいかがですか？',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _action(
                  '良い',
                  () => _press('health', '${widget.state.healthTime}', '1'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _action(
                  '普通',
                  () => _press('health', '${widget.state.healthTime}', '2'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _action(
                  '悪い',
                  () => _press('health', '${widget.state.healthTime}', '3'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (widget.state.showDayService) ...[
          Padding(
            // 5px 下げる。確認したとの間隔は相殺。
            padding: const EdgeInsets.only(top: 5, bottom: 3),
            child: Text(
              '今日のデイサービスの時間は${widget.state.dayServiceText}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: daySize, fontWeight: FontWeight.bold),
            ),
          ),
          if (widget.state.showDayServiceCheck)
            Center(
              child: SizedBox(
                width: 280,
                child: _action(
                  '確認した',
                  () => _press(
                      'dayservice', '${widget.state.dayServiceTime}', '1'),
                ),
              ),
            ),
        ],
        if (!widget.state.hasAny)
          const Text(
            'いま表示するお知らせはありません',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24),
          ),
      ],
    );

    return FocusScope(
      node: _scope,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.of(context).size.width;
          final bodyW = (maxW * 0.72).clamp(320.0, 900.0);
          return Stack(
            children: [
              // 背景タップで裏のメニューが反応しないようにする
              const Positioned.fill(
                child: ModalBarrier(dismissible: false, color: Colors.transparent),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: widget.compact ? 8 : 16,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: bodyW),
                    child: body,
                  ),
                ),
              ),
              if (widget.onBack != null)
                Positioned(
                  top: 8,
                  right: 16,
                  child: SizedBox(
                    width: 160,
                    height: _backHeight,
                    child: TvPiFocusButton(
                      label: '戻る',
                      onPressed: widget.onBack!,
                      color: const Color(0xFF666666),
                      autofocus: TvUtil.isTelevision,
                      focusNode: _backFocus,
                      padding: EdgeInsets.zero,
                      fontSize: _backFont,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _action(String label, VoidCallback onPressed) {
    return SizedBox(
      height: _actionHeight,
      child: TvPiFocusButton(
        label: label,
        onPressed: onPressed,
        color: const Color(0xFF5CB85C),
        padding: EdgeInsets.zero,
        fontSize: _actionFont,
      ),
    );
  }
}
