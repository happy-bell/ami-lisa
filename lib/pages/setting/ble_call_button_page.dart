import 'package:amiapp/ble/scbtn_protocol.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/scbtn_call_button_service.dart';
import 'package:amiapp/widgets/tv_focusable.dart';
import 'package:flutter/material.dart';

/// TV設定のコールボタン確認。
/// 登録・削除は管理画面（基本設定 → コールボタン）。ここは一覧の確認と電波の確認。
class BleCallButtonPage extends StatefulWidget {
  const BleCallButtonPage({super.key});

  @override
  State<BleCallButtonPage> createState() => _BleCallButtonPageState();
}

class _BleCallButtonPageState extends State<BleCallButtonPage> {
  bool _loading = false;
  bool _scanning = false;
  String _status = '';
  List<ScbtnAdvertisement> _found = [];

  @override
  void initState() {
    super.initState();
    ScbtnCallButtonService.instance.addListener(_onChanged);
    _reload();
  }

  @override
  void dispose() {
    ScbtnCallButtonService.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _status = '管理画面の登録を読み込んでいます…';
    });
    final ok = await ScbtnCallButtonService.instance.refreshList(force: true);
    if (!mounted) return;
    final n = ScbtnCallButtonService.instance.registeredIds.length;
    setState(() {
      _loading = false;
      _status = ok
          ? (n == 0
              ? '登録がありません。管理画面の基本設定 → コールボタンで登録してください。'
              : '$n 台登録されています')
          : '一覧を取得できませんでした（前回の登録があればそれを使います）';
    });
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _status = 'ボタンを探しています…（ボタンを押すと見つかりやすいです）';
      _found = [];
    });
    final list = await ScbtnCallButtonService.instance.scanNearby();
    if (!mounted) return;
    setState(() {
      _found = list;
      _scanning = false;
      _status = list.isEmpty
          ? '見つかりませんでした。ボタンを押してから再度検索してください。'
          : '${list.length} 台見つかりました';
    });
  }

  @override
  Widget build(BuildContext context) {
    final svc = ScbtnCallButtonService.instance;
    final buttons = svc.devices.where((d) => d.deviceType == 1).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        title: const Text('コールボタン'),
        backgroundColor: const Color(0xFF3D5A80),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(32, 20, 32, 32),
        children: [
          _field('ユーザーコード', AppManager.delegatorCode),
          _field('マスタID', AppManager.myId),
          const SizedBox(height: 8),
          const Text(
            '登録・削除は管理画面の「基本設定 → コールボタン」で行います。',
            style: TextStyle(fontSize: 16, color: Color(0xFF555555)),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _action('一覧を再読込', _reload, autofocus: true),
              _action('近くのボタンを検索', _scan),
            ],
          ),
          const SizedBox(height: 16),
          Text(_status, style: const TextStyle(fontSize: 18)),
          if (_loading || _scanning)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          const SizedBox(height: 20),
          const Text('管理画面の登録', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          if (buttons.isEmpty)
            const Text('なし', style: TextStyle(fontSize: 18, color: Colors.grey)),
          for (final d in buttons)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: Text(
                  d.name.isEmpty ? d.deviceId : '${d.deviceId}  ${d.name}',
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
          const SizedBox(height: 20),
          const Text('近くで見つかったボタン', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          for (final b in _found)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${b.id}  MAC ${b.mac}  電池 ${b.battery ?? '-'}%',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                    Text(
                      svc.isRegistered(b)
                          ? (b.pressed ? '登録済・押下中' : '登録済')
                          : '未登録',
                      style: TextStyle(
                        fontSize: 16,
                        color: svc.isRegistered(b)
                            ? (b.pressed ? Colors.red : const Color(0xFF2E7D32))
                            : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: const TextStyle(fontSize: 18)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
  }

  Widget _action(String label, VoidCallback onTap, {bool autofocus = false}) {
    return TvFocusable(
      autofocus: autofocus,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        color: const Color(0xFF3D5A80),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
    );
  }
}
