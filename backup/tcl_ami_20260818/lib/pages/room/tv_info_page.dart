import 'dart:convert';

import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/widgets/tv_focusable.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

/// ラズパイ版のお知らせ（広報・ハザードマップ）。TCLアミ／スタッフからは開かない。
class TvInfoPage extends StatefulWidget {
  const TvInfoPage({super.key});

  @override
  State<TvInfoPage> createState() => _TvInfoPageState();
}

class _TvInfoPageState extends State<TvInfoPage> {
  bool _loading = true;
  List<String> _messages = [];
  List<String> _files = [];
  String _video = '';
  VideoPlayerController? _player;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
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
          _messages = messages;
          _files = files;
          _video = video == 'null' ? '' : video;
        }
      }
    } catch (e) {
      print('[TvInfo] load error $e');
    }
    if (_video.isNotEmpty) {
      await _startVideo();
    }
    if (mounted) {
      setState(() => _loading = false);
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

  Future<void> _toggleVideo() async {
    final player = _player;
    if (player == null) return;
    if (player.value.isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
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
                      TvFocusable(
                        autofocus: TvUtil.isTelevision,
                        onPressed: () => Navigator.of(context).pop(),
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5CB85C),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(120, 56),
                          ),
                          child: const Text('戻る',
                              style: TextStyle(fontSize: 22)),
                        ),
                      ),
                      if (_player != null) ...[
                        const SizedBox(height: 12),
                        TvFocusable(
                          onPressed: _toggleVideo,
                          child: ElevatedButton(
                            onPressed: _toggleVideo,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _playing
                                  ? const Color(0xFFCC3333)
                                  : const Color(0xFFFF9900),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(120, 56),
                            ),
                            child: Text(_playing ? '停止' : '再生',
                                style: const TextStyle(fontSize: 22)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(child: _content()),
              ],
            ),
    );
  }

  Widget _content() {
    if (_messages.isEmpty && _files.isEmpty && _player == null) {
      return const Center(
        child: Text('いま表示するお知らせはありません', style: TextStyle(fontSize: 24)),
      );
    }
    return ListView(
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
