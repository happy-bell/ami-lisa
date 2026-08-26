import 'package:amiapp/ble/checkme_pro_ble.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/services/checkme_pro_service.dart';
import 'package:amiapp/services/checkme_ring_service.dart';
import 'package:amiapp/widgets/tv_focusable.dart';
import 'package:flutter/material.dart';

/// TCLアミの Checkme Pro BLEテスト。スタッフ／ラズパイ版の自動処理には使わない。
class SettingCheckmeProPage extends StatefulWidget {
  const SettingCheckmeProPage({super.key});

  @override
  State<SettingCheckmeProPage> createState() => _SettingCheckmeProPageState();
}

class _SettingCheckmeProPageState extends State<SettingCheckmeProPage> {
  final CheckmeProBle _ble = CheckmeProBle();
  String _androidId = '';

  @override
  void initState() {
    super.initState();
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
  double get _valueSize => _tv ? 56.0 : 32.0;

  @override
  Widget build(BuildContext context) {
    final data = _ble.lastRealtime;
    return Scaffold(
      appBar: WidgetUtil.appBar(
        'Checkme Pro（BLEテスト）',
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
              '本体で「チェックモニター」を起動してからスキャン→接続します。',
              style: TextStyle(fontSize: _tv ? 18 : 13, color: Colors.black87),
            ),
            if (_androidId.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'テレビID: $_androidId',
                  style:
                      TextStyle(fontSize: _tv ? 16 : 12, color: Colors.black54),
                ),
              ),
            const SizedBox(height: 12),
            Text(_ble.status, style: TextStyle(fontSize: _titleSize)),
            const SizedBox(height: 12),
            Row(
              children: [
                _actionButton(
                  label: _ble.scanning ? 'スキャン中' : 'スキャン',
                  onPressed: _ble.scanning ? null : _ble.startScan,
                  autofocus: true,
                ),
                const SizedBox(width: 12),
                _actionButton(
                  label: '切断',
                  onPressed: _ble.connected ? _ble.disconnect : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'HR ${_n(data?.hr)}    SpO2 ${_n(data?.spo2)}    '
              'PR ${_n(data?.pr)}    PI ${_pi(data?.pi)}',
              style: TextStyle(
                fontSize: _valueSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'パケット ${_ble.packets}',
              style: TextStyle(fontSize: _tv ? 18 : 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            for (final d in _ble.sortedDevices) _deviceRow(d),
            const SizedBox(height: 16),
            for (final line in _ble.logs.take(12))
              Text(line, style: TextStyle(fontSize: _tv ? 14 : 11)),
          ],
        ),
      ),
    );
  }

  String _n(int? v) => v?.toString() ?? '-';
  String _pi(double? v) => v == null ? '-' : v.toStringAsFixed(1);

  Widget _deviceRow(CheckmeProScanDevice d) {
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
                  Text(
                    '${d.isPro ? "[Pro] " : ""}${d.name}',
                    style: TextStyle(fontSize: _tv ? 22 : 15),
                  ),
                  Text(
                    '${d.id}   RSSI ${d.rssi}',
                    style: TextStyle(
                        fontSize: _tv ? 16 : 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            Text(
              _ble.connected && _ble.connectedName == d.name ? '接続中' : '接続',
              style: TextStyle(fontSize: _tv ? 20 : 14, color: Colors.blue),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required VoidCallback? onPressed,
    bool autofocus = false,
  }) {
    return TvFocusable(
      autofocus: autofocus,
      enabled: onPressed != null,
      onPressed: onPressed,
      child: ElevatedButton(
        onPressed: onPressed,
        child: Text(label, style: TextStyle(fontSize: _tv ? 20 : 14)),
      ),
    );
  }
}
