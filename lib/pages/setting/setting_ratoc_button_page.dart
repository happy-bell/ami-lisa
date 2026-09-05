import 'package:flutter/material.dart';

import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/services/ratoc_button_service.dart';
import 'package:amiapp/services/ratoc_button_store.dart';
import 'package:amiapp/widgets/tv_focusable.dart';

/// スマートボタン（ラトック RS-SCBTN2）を登録する画面。
///
/// 登録した1台だけを聞き取る。近所に同じ製品があっても拾わない。
/// 未登録のあいだは一切スキャンしないので、リモコンに影響しない。
class SettingRatocButtonPage extends StatefulWidget {
  const SettingRatocButtonPage({super.key});

  @override
  State<SettingRatocButtonPage> createState() => _SettingRatocButtonPageState();
}

class _SettingRatocButtonPageState extends State<SettingRatocButtonPage> {
  static const _rowHeight = 62.0;
  static const _titleStyle = TextStyle(fontSize: 18.0, color: Colors.black);
  static const _subStyle = TextStyle(fontSize: 14.0, color: Colors.grey);
  static const _macStyle = TextStyle(
    fontSize: 16.0,
    color: Colors.black87,
    fontFamily: 'monospace',
  );

  List<RatocFound> _found = [];
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  /// 近くのボタンを数秒だけ探す。短く回して必ず止める。
  Future<void> _search() async {
    setState(() => _scanning = true);
    final list = await RatocButtonService.instance.discover();
    if (!mounted) return;
    setState(() {
      _found = list;
      _scanning = false;
    });
  }

  Future<void> _register(RatocFound d) async {
    final yes = await _confirm('${d.name.isEmpty ? d.deviceId : d.name} を'
        '呼び出しボタンとして登録します。よろしいですか。');
    if (!yes) return;
    await RatocButtonStore.instance.save(d.deviceId, d.name);
    await RatocButtonService.instance.stop();
    await RatocButtonService.instance.start();
    if (!mounted) return;
    setState(() {});
    _tell('登録しました');
  }

  Future<void> _unregister() async {
    final yes = await _confirm('登録を外します。よろしいですか。');
    if (!yes) return;
    await RatocButtonService.instance.stop();
    await RatocButtonStore.instance.clear();
    if (!mounted) return;
    setState(() {});
    _tell('登録を外しました');
  }

  Future<bool> _confirm(String message) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('確認'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('いいえ'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('はい'),
          ),
        ],
      ),
    );
    return r == true;
  }

  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Widget _heading(String text) => Container(
        color: const Color.fromARGB(255, 240, 240, 240),
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
        width: double.infinity,
        child: Text(text, style: _subStyle),
      );

  Widget _row({
    required String title,
    required String sub,
    required Widget trailing,
    required VoidCallback onActivate,
    bool autofocus = false,
  }) {
    return TvSettingFocus(
      autofocus: autofocus,
      onActivate: onActivate,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Color.fromARGB(255, 220, 220, 220)),
          ),
        ),
        height: _rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _titleStyle),
                  Text(sub, style: _macStyle),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = RatocButtonStore.instance;
    final others =
        _found.where((d) => !store.matches(d.deviceId)).toList();

    final rows = <Widget>[
      _heading('登録済み'),
      if (!store.isRegistered)
        Container(
          height: _rowHeight,
          padding: const EdgeInsets.all(10.0),
          alignment: Alignment.centerLeft,
          child: const Text('ありません（この間はスキャンしません）',
              style: _subStyle),
        )
      else
        _row(
          title: store.name.isEmpty ? store.mac : store.name,
          sub: store.mac,
          trailing: const Text('外す',
              style: TextStyle(fontSize: 16.0, color: Colors.red)),
          onActivate: _unregister,
          autofocus: true,
        ),
      _heading(_scanning ? '探しています…' : '近くにあるボタン'),
      if (!_scanning && others.isEmpty)
        Container(
          height: _rowHeight,
          padding: const EdgeInsets.all(10.0),
          alignment: Alignment.centerLeft,
          child: const Text('見つかりません。ボタンを押してから探し直してください',
              style: _subStyle),
        ),
      for (var i = 0; i < others.length; i++)
        _row(
          title: others[i].name.isEmpty ? others[i].deviceId : others[i].name,
          sub: '${others[i].deviceId}　電波 ${others[i].rssi}'
              '${others[i].battery >= 0 ? '　電池 ${others[i].battery}%' : ''}',
          trailing: const Text('登録',
              style: TextStyle(fontSize: 16.0, color: Colors.blue)),
          onActivate: () => _register(others[i]),
          autofocus: !store.isRegistered && i == 0,
        ),
      _row(
        title: 'もう一度探す',
        sub: 'ボタンを押しながら選ぶと見つかりやすくなります',
        trailing: const Icon(Icons.refresh, color: Colors.grey),
        onActivate: _scanning ? () {} : _search,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('呼び出しボタン'),
        automaticallyImplyLeading: !TvUtil.isTelevision,
      ),
      body: ListView(children: rows),
    );
  }
}
