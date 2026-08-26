import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:amiapp/pages/lisa/lisa_activation_page.dart';

/// 利用規約とプライバシーポリシーの同意画面。
///
/// 左に本文（タブで切替）、右に説明とボタン。テレビの横長画面に合わせている。
/// リモコンで操作するため、フォーカスの位置が一目で分かるようにしている。
class LisaTermsPage extends StatefulWidget {
  const LisaTermsPage({super.key});

  @override
  State<LisaTermsPage> createState() => _LisaTermsPageState();
}

class _LisaTermsPageState extends State<LisaTermsPage> {
  /// 0 = 利用規約 / 1 = プライバシーポリシー
  int _tab = 0;

  /// 規約本文。アプリに直書きせず assets のテキストから読む。
  /// 改定のたびにアプリを作り直さずに済むようにするため。
  String _terms = '読み込んでいます…';
  String _privacy = '読み込んでいます…';

  final ScrollController _scroll = ScrollController();

  final FocusNode _termsTabFocus = FocusNode(debugLabel: 'termsTab');
  final FocusNode _privacyTabFocus = FocusNode(debugLabel: 'privacyTab');
  final FocusNode _agreeFocus = FocusNode(debugLabel: 'agree');
  final FocusNode _exitFocus = FocusNode(debugLabel: 'exit');
  final FocusNode _bodyFocus = FocusNode(debugLabel: 'termsBody');

  /// タブの選択色。「同意する」のフォーカス色もこれに揃える。
  static const _tabBlue = Color(0xFF6B70BE);

  /// 規約の配布先。改定時はここのファイルを差し替えるだけでよい。
  static const _legalBase = 'https://fun-talk.net/legal/';

  @override
  void initState() {
    super.initState();
    _loadTexts();
    // 最初は「同意する」にフォーカスを置く。読みたい人はタブへ移動できる。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _agreeFocus.requestFocus();
    });
  }

  /// 規約を読み込む。まずサーバー、駄目ならアプリ内の控えを使う。
  ///
  /// サーバーを先に見るのは、改定をアプリ更新なしで反映するため。
  /// 通信できない家庭でも同意画面が空にならないよう、控えを必ず持たせている。
  Future<void> _loadTexts() async {
    final terms = await _fetch('terms.txt', 'assets/legal/terms.txt');
    final privacy = await _fetch('privacy.txt', 'assets/legal/privacy.txt');
    if (!mounted) return;
    setState(() {
      _terms = terms;
      _privacy = privacy;
    });
  }

  Future<String> _fetch(String name, String fallbackAsset) async {
    try {
      final res = await http
          .get(Uri.parse('$_legalBase$name'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        // サーバーが文字コードを返さないことがあるため UTF-8 を明示する。
        final text = utf8.decode(res.bodyBytes, allowMalformed: true);
        if (text.trim().isNotEmpty) {
          // ignore: avoid_print
          print('[Lisa] 規約をサーバーから取得 $name');
          return text;
        }
      }
      // ignore: avoid_print
      print('[Lisa] 規約 $name status=${res.statusCode} → 内蔵版を使用');
    } catch (e) {
      // ignore: avoid_print
      print('[Lisa] 規約の取得に失敗 $name $e → 内蔵版を使用');
    }
    try {
      return await rootBundle.loadString(fallbackAsset);
    } catch (_) {
      return '規約を読み込めませんでした。';
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _termsTabFocus.dispose();
    _privacyTabFocus.dispose();
    _agreeFocus.dispose();
    _exitFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // 操作
  // ------------------------------------------------------------------

  Future<void> _agree() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isInitialized', true);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LisaActivationPage(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  /// アプリを閉じてテレビのホームへ戻す。
  void _exit() {
    SystemNavigator.pop();
  }

  void _scrollBy(int direction) {
    if (!_scroll.hasClients) return;
    final target = (_scroll.offset + direction * 260)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
  }

  void _selectTab(int index) {
    if (_tab == index) return;
    setState(() => _tab = index);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  // ------------------------------------------------------------------
  // 画面
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(44, 28, 44, 28),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: _left()),
              const SizedBox(width: 40),
              Expanded(flex: 5, child: _right()),
            ],
          ),
        ),
      ),
    );
  }

  // 左：タブと本文
  Widget _left() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _tabButton('利用規約', 0, _termsTabFocus)),
            Expanded(child: _tabButton('プライバシーポリシー', 1, _privacyTabFocus)),
          ],
        ),
        const SizedBox(height: 18),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _tabButton(String label, int index, FocusNode node) {
    final selected = _tab == index;
    return Focus(
      focusNode: node,
      onKeyEvent: (n, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          _selectTab(index);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () => _selectTab(index),
            child: Container(
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? _tabBlue : Colors.black,
                border: Border.all(
                  color: focused ? Colors.white : const Color(0xFF888888),
                  width: focused ? 3 : 1,
                ),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body() {
    return Focus(
      focusNode: _bodyFocus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowDown) {
          _scrollBy(1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          _scrollBy(-1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: focused ? _tabBlue : Colors.transparent,
                width: 3,
              ),
            ),
            padding: const EdgeInsets.all(10),
            child: SingleChildScrollView(
              controller: _scroll,
              child: Text(
                _tab == 0 ? _terms : _privacy,
                style: const TextStyle(
                  fontSize: 17,
                  height: 1.75,
                  color: Colors.white,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // 右：説明とボタン
  //
  // 文章の改行はテキストに任せる。手で改行を入れると、
  // 画面の幅や文字の大きさが変わったとき中途半端な位置で折り返す。
  Widget _right() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ロゴ。どのサービスの規約なのかが一目で分かるようにする。
        Image.asset(
          'assets/lisa_logo.png',
          height: 78,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox(height: 78),
        ),
        const SizedBox(height: 18),
        const Text(
          'テレビ電話　見守り・健康管理・ハザードマップ',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 23, color: Colors.white, height: 1.4),
        ),
        const SizedBox(height: 22),
        const Text(
          'テレビ電話ａｍｉシリーズ（LiSA）のご利用には、'
          '利用規約、プライバシーポリシーの同意が必要です。'
          '内容をお読みいただき、同意ボタンを押してサービスを'
          'ご利用ください。',
          style: TextStyle(fontSize: 19, color: Colors.white, height: 1.8),
        ),
        const Spacer(),
        _actionButton('同意する', _agreeFocus, _agree, primary: true),
        const SizedBox(height: 18),
        _actionButton('終了する', _exitFocus, _exit, primary: false),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _actionButton(String label, FocusNode node, VoidCallback onPressed,
      {required bool primary}) {
    return Focus(
      focusNode: node,
      onKeyEvent: (n, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onPressed,
            child: Container(
              width: primary ? 300 : 220,
              height: primary ? 74 : 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // フォーカス中はタブと同じ青にする。どこを選んでいるか一目で分かる。
                color: focused ? _tabBlue : const Color(0xFF4A4A4A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: focused ? Colors.white : Colors.transparent,
                  width: 3,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: primary ? 28 : 22,
                  color: Colors.white,
                  fontWeight: focused ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
