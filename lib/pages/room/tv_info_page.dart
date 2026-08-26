import 'dart:convert';

import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/pages/room/hazard_map_page.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/widgets/tv_pi_focus_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

/// ラズパイ版のお知らせ（広報・ハザードマップ）。TCLアミ／スタッフからは開かない。
class TvInfoPage extends StatefulWidget {
  const TvInfoPage({super.key, this.autoPlayAudio = true});

  /// 音声のみのお知らせを開いた直後に自動再生するか。
  /// 時間指定の自動配信は true（勝手に読み上げが始まってよい）。
  /// ホームの「広報配信」ボタンから開いたときは false にして、
  /// 利用者が「再生」を押すまで鳴らさない。
  final bool autoPlayAudio;

  @override
  State<TvInfoPage> createState() => _TvInfoPageState();
}

class _TvInfoPageState extends State<TvInfoPage> {
  bool _loading = true;
  List<String> _messages = [];
  List<String> _files = [];
  String _video = '';
  String _audio = '';
  VideoPlayerController? _player;
  /// 音声のみのお知らせ用（映像は表示しない）。
  VideoPlayerController? _audioPlayer;
  /// TV(リモコン)で本文をスクロールするための制御。
  final ScrollController _scrollController = ScrollController();
  final FocusNode _contentFocus = FocusNode(debugLabel: 'tvInfoContent');
  bool _contentFocused = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player?.dispose();
    _audioPlayer?.dispose();
    _scrollController.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  /// D-pad上下でスクロール。direction=1で下、-1で上。
  void _scrollBy(int direction) {
    if (!_scrollController.hasClients) return;
    const step = 260.0;
    final target = (_scrollController.offset + direction * step)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
    );
  }

  Future<void> _load() async {
    final url =
        '${AppDefine.baseURL}api/master_info?code=${AppManager.delegatorCode}';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map) {
          final messages = <String>[];
          final rawMessages = data['messages'];
          if (rawMessages is List) {
            for (final item in rawMessages) {
              final text = item?.toString() ?? '';
              if (text.isNotEmpty && text != 'null') messages.add(text);
            }
          }
          final files = <String>[];
          final rawFiles = data['files'];
          if (rawFiles is List) {
            for (final item in rawFiles) {
              final path = item?.toString() ?? '';
              if (path.isNotEmpty && path != 'null') files.add(path);
            }
          }
          final video = (data['video'] ?? '').toString();
          final audio = (data['audio'] ?? '').toString();
          _messages = messages;
          _files = files;
          _video = video == 'null' ? '' : video;
          _audio = audio == 'null' ? '' : audio;
        }
      }
    } catch (e) {
      print('[TvInfo] load error $e');
    }
    if (_video.isNotEmpty) {
      await _startVideo();
    } else if (_audio.isNotEmpty) {
      // 動画が無く音声だけのお知らせ（読み上げ音声）。自動配信のときだけ鳴らす。
      await _startAudio(autoPlay: widget.autoPlayAudio);
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  /// 音声のみのお知らせを再生する。webm など動画コンテナの音声も
  /// VideoPlayer で扱えるため、映像なしで再生する（追加パッケージ不要）。
  /// [autoPlay] が false のときは読み込みだけ行い、再生はしない。
  /// 「再生」ボタンを押せばそのまま鳴らせる状態にしておく。
  Future<void> _startAudio({bool autoPlay = true}) async {
    // 音声は image? ではなく audio? で取得する（image? は500を返す）。
    final url = '${AppDefine.baseURL}audio?path=$_audio';
    print('[TvInfo] start audio $url autoPlay=$autoPlay');
    final player = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await player.initialize();
      if (autoPlay) await player.play();
      _audioPlayer = player;
      _playing = autoPlay;
      player.addListener(() {
        if (!mounted) return;
        setState(() {
          _playing = player.value.isPlaying;
        });
      });
    } catch (e) {
      print('[TvInfo] audio error $e');
      player.dispose();
    }
  }

  Future<void> _startVideo() async {
    final url = '${AppDefine.baseURL}image?path=$_video';
    final player = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await player.initialize();
      await player.play();
      _player = player;
      _playing = true;
      player.addListener(() {
        if (!mounted) return;
        setState(() {
          _playing = player.value.isPlaying;
        });
      });
    } catch (e) {
      print('[TvInfo] video error $e');
      player.dispose();
    }
  }

  /// 停止／再生。動画が無い場合は音声のお知らせを対象にする。
  Future<void> _toggleVideo() async {
    final player = _player ?? _audioPlayer;
    if (player == null) return;
    if (player.value.isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  /// ハザードマップへ遷移する。再生中の広報動画は先に止める
  /// （遷移後も音声だけ流れ続けるのを防ぐ）。
  Future<void> _openHazardMap() async {
    final player = _player ?? _audioPlayer;
    if (player != null && player.value.isPlaying) {
      await player.pause();
      if (mounted) setState(() => _playing = false);
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HazardMapPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: WidgetUtil.appBar(
        '広報・ハザードマップ配信',
        backgroundColor: WidgetUtil.iosNavbarBG,
        foregroundColor: Colors.black,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                SizedBox(
                  width: 180,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _sideBtn(
                        '戻る',
                        const Color(0xFF5CB85C),
                        () => Navigator.of(context).pop(),
                        autofocus: TvUtil.isTelevision,
                      ),
                      if (_player != null || _audioPlayer != null)
                        _sideBtn(
                          _playing ? '停止' : '再生',
                          _playing
                              ? const Color(0xFFCC3333)
                              : const Color(0xFFFF9900),
                          _toggleVideo,
                        ),
                      // 「ハザードマップ」は7文字。サイドバー幅180pxで省略されない
                      // よう、このボタンだけ文字を小さくする。
                      _sideBtn(
                        'ハザードマップ',
                        const Color(0xFF404040),
                        _openHazardMap,
                        fontSize: 17,
                      ),
                    ],
                  ),
                ),
                Expanded(child: _contentArea()),
              ],
            ),
    );
  }

  Widget _sideBtn(String label, Color color, VoidCallback onPressed,
      {bool autofocus = false, double fontSize = 22}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 56,
        child: TvPiFocusButton(
          label: label,
          onPressed: onPressed,
          color: color,
          autofocus: autofocus,
          fontSize: fontSize,
          borderRadius: 10,
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }

  /// 本文エリア。TVではリモコン上下でスクロールできるようにする。
  /// スマホ／タッチ環境は従来どおり指でスクロールする。
  Widget _contentArea() {
    final content = _content();
    if (!TvUtil.isTelevision) return content;
    return Focus(
      focusNode: _contentFocus,
      onFocusChange: (has) {
        if (mounted && has != _contentFocused) {
          setState(() => _contentFocused = has);
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.pageDown) {
          _scrollBy(1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.pageUp) {
          _scrollBy(-1);
          return KeyEventResult.handled;
        }
        // 左キーで左メニュー（戻る／ハザードマップ等）へフォーカスを戻す。
        if (key == LogicalKeyboardKey.arrowLeft) {
          node.focusInDirection(TraversalDirection.left);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          border: Border.all(
            color:
                _contentFocused ? const Color(0xFF0099FF) : Colors.transparent,
            width: 3,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: content,
      ),
    );
  }

  Widget _content() {
    if (_messages.isEmpty &&
        _files.isEmpty &&
        _player == null &&
        _audioPlayer == null) {
      return const Center(
        child: Text('いま表示するお知らせはありません', style: TextStyle(fontSize: 24)),
      );
    }
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(24),
      children: [
        for (final message in _messages)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(message, style: const TextStyle(fontSize: 26)),
          ),
        for (final file in _files)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Image.network(
              '${AppDefine.baseURL}image?path=$file',
              fit: BoxFit.contain,
            ),
          ),
        if (_player != null && _player!.value.isInitialized)
          AspectRatio(
            aspectRatio: _player!.value.aspectRatio == 0
                ? 16 / 9
                : _player!.value.aspectRatio,
            child: VideoPlayer(_player!),
          ),
      ],
    );
  }
}
