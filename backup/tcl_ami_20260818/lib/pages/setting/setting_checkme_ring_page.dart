import 'package:amiapp/ble/checkme_ring_ble.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/services/checkme_pro_service.dart';
import 'package:amiapp/services/checkme_ring_service.dart';
import 'package:amiapp/widgets/tv_focusable.dart';
import 'package:flutter/material.dart';

class SettingCheckmeRingPage extends StatefulWidget {
  const SettingCheckmeRingPage({super.key});

  @override
  State<SettingCheckmeRingPage> createState() => _SettingCheckmeRingPageState();
}

class _SettingCheckmeRingPageState extends State<SettingCheckmeRingPage> {
  final CheckmeRingBle _ble = CheckmeRingBle();

  String _androidId = '';

  @override
  void initState() {
    super.initState();
    // 自動測定サービスと同時にGATTを掴まないよう、この画面の間は止める
    CheckmeRingService.instance.pause();
    CheckmeProService.instance.pause();
    _ble.onChanged = () {
      if (mounted) setState(() {});
    };
    TvUtil.getAndroidId().then((id) {
      if (mounted) setState(() => _androidId = id);
    });
  }

  @override
  void dispose() {
    _ble.dispose();
    CheckmeProService.instance.resume();
    CheckmeRingService.instance.resume();
    super.dispose();
  }

  bool get _tv => TvUtil.isTelevision;

  double get _titleSize => _tv ? 22.0 : 16.0;

  double get _valueSize => _tv ? 72.0 : 40.0;

  Future<void> _scan() async {
    await _ble.startScan();
  }

  @override
  Widget build(BuildContext context) {
    final data = _ble.lastRealtime;
    return Scaffold(
      appBar: WidgetUtil.appBar(
        'Checkme Ring（BLEテスト）',
        backgroundColor: WidgetUtil.iosNavbarBG,
        foregroundColor: Colors.black,
      ),
      backgroundColor: const Color.fromARGB(255, 240, 240, 240),
      body: FocusTraversalGroup(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              'テレビのBluetooth設定ではペアリングしないでください。'
              '指を入れてから「スキャン」→機器を選んで接続します。',
              style: TextStyle(fontSize: _tv ? 18 : 13, color: Colors.black87),
            ),
            if (_androidId.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'テレビシリアル: $_androidId  ※ami_serial_nos に code と mst_id を付けて登録します',
                  style:
                      TextStyle(fontSize: _tv ? 16 : 12, color: Colors.black54),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              _ble.status,
              style: TextStyle(
                fontSize: _tv ? 26 : 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _actionButton(
                  label: _ble.scanning ? 'スキャン中' : 'スキャン',
                  autofocus: _tv,
                  enabled: !_ble.scanning && !_ble.connecting,
                  onPressed: _scan,
                ),
                const SizedBox(width: 16),
                _actionButton(
                  label: '切断',
                  enabled: _ble.connected || _ble.connecting,
                  onPressed: _ble.disconnect,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _valuesCard(data),
            const SizedBox(height: 16),
            Text('見つかった機器', style: TextStyle(fontSize: _titleSize)),
            const SizedBox(height: 8),
            if (_ble.sortedDevices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _ble.scanning ? '探しています...' : 'まだありません。スキャンしてください。',
                  style: TextStyle(fontSize: _tv ? 20 : 14),
                ),
              ),
            ..._ble.sortedDevices.map(_deviceRow),
            const SizedBox(height: 16),
            Text('ログ', style: TextStyle(fontSize: _titleSize)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _ble.logs.isEmpty ? '（なし）' : _ble.logs.join('\n'),
                style: TextStyle(
                  fontSize: _tv ? 16 : 12,
                  color: Colors.greenAccent,
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _valuesCard(dynamic data) {
    final worn = data?.wearLabel ?? '—';
    final valid = data == null ? '' : (data.isValid ? '有効' : '無効（指を入れてください）');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _metric('SpO2', data == null ? '—' : '${data.spo2}', '%'),
              const SizedBox(width: 32),
              _metric('脈拍', data == null ? '—' : '${data.pulse}', 'bpm'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '装着: $worn    PI: ${data?.pi ?? "—"}    電池: ${data?.battery ?? "—"}    $valid',
            style: TextStyle(fontSize: _tv ? 20 : 14),
          ),
          if (_ble.lastHex.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _ble.lastHex,
                style: TextStyle(fontSize: _tv ? 14 : 11, color: Colors.black54),
              ),
            ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, String unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: _tv ? 20 : 13)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: _valueSize,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 8),
              child: Text(unit, style: TextStyle(fontSize: _tv ? 22 : 14)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _deviceRow(CheckmeRingScanDevice d) {
    final title = '${d.isRing ? "[Ring] " : ""}${d.name}';
    final sub = '${d.id}   RSSI ${d.rssi}';
    return TvSettingFocus(
      onActivate: () => _ble.connect(d),
      child: Container(
        height: _tv ? 72 : 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: _tv ? 22 : 15)),
                  Text(sub, style: TextStyle(fontSize: _tv ? 16 : 12, color: Colors.black54)),
                ],
              ),
            ),
            Text(
              _ble.connected && _ble.connectedName == d.name ? '接続中' : '接続',
              style: TextStyle(
                fontSize: _tv ? 20 : 14,
                color: Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required VoidCallback onPressed,
    bool enabled = true,
    bool autofocus = false,
  }) {
    return TvFocusable(
      autofocus: autofocus,
      enabled: enabled,
      onPressed: enabled ? onPressed : null,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          minimumSize: Size(_tv ? 180 : 120, _tv ? 56 : 44),
          textStyle: TextStyle(fontSize: _tv ? 22 : 16),
        ),
        child: Text(label),
      ),
    );
  }
}
