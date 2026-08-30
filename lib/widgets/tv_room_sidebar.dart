import 'package:amiapp/services/checkme_pro_service.dart';
import 'package:amiapp/services/checkme_ring_service.dart';
import 'package:amiapp/widgets/no_camera_banner.dart';
import 'package:amiapp/widgets/tv_pi_focus_button.dart';
import 'package:flutter/material.dart';

/// ラズパイ Web（46amip4）と同じ右サイドバー。
class TvRoomSidebar extends StatelessWidget {
  const TvRoomSidebar({
    super.key,
    required this.displayName,
    required this.hasVideo,
    required this.videoPlaying,
    required this.onHome,
    required this.onCall,
    required this.onGroupCall,
    required this.onVideo,
    required this.onHealth,
    required this.onInfo,
    required this.onClock,
    required this.onSetting,
    required this.onRing,
    required this.onCheckme,
    this.homeFocusNode,
    this.videoFocusNode,
    this.ringFocusNode,
    this.checkmeFocusNode,
    this.showVitals = true,
    this.bpHigh = '-',
    this.bpLow = '-',
    this.bpPulse = '-',
    this.temp = '-',
    this.weight = '-',
    this.roomTemp = '-',
    this.roomHum = '-',
    this.spo2 = '-',
    this.pr = '-',
    this.hr = '-',
    this.pi = '-',
    this.showNoCamera = false,
  });

  final String displayName;
  final bool hasVideo;
  final bool videoPlaying;
  final VoidCallback onHome;
  final VoidCallback onCall;
  final VoidCallback onGroupCall;
  final VoidCallback onVideo;
  final VoidCallback onHealth;
  final VoidCallback onInfo;
  final VoidCallback onClock;
  final VoidCallback onSetting;
  final VoidCallback onRing;
  final VoidCallback onCheckme;
  final FocusNode? homeFocusNode;
  final FocusNode? videoFocusNode;
  /// Ring/Checkme はラベルが「停止」に変わるとウィジェットが作り直され、
  /// フォーカスが外れて別ボタンへ飛ぶ。外から FocusNode を渡して保持する。
  final FocusNode? ringFocusNode;
  final FocusNode? checkmeFocusNode;
  final bool showVitals;
  final String bpHigh;
  final String bpLow;
  final String bpPulse;
  final String temp;
  final String weight;
  final String roomTemp;
  final String roomHum;
  final String spo2;
  final String pr;
  final String hr;
  final String pi;
  final bool showNoCamera;

  static const _gap = 2.0;

  /// ホーム右列のメニュー＋Ring行を除いたバイタル表の高さ。通話中も同じ長さにする。
  static double estimateVitalHeight(
    double screenHeight, {
    double top = 8,
    double bottom = 8,
    bool hasVideo = false,
  }) {
    const padV = 6.0;
    const font = 16.0;
    final btnH = padV * 2 + font * 1.1 + _gap;
    final menus = 7 + (hasVideo ? 1 : 0) + 1 + 1;
    return (screenHeight - top - bottom - menus * btnH)
        .clamp(160.0, screenHeight);
  }

  @override
  Widget build(BuildContext context) {
    final ring = CheckmeRingService.instance;
    final pro = CheckmeProService.instance;
    final spo2Text = ring.spo2?.toString() ?? spo2;
    final prText = ring.pulse?.toString() ?? pr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _menu('ホーム', onHome,
            autofocus: !videoPlaying,
            focusNode: homeFocusNode,
            buttonKey: const ValueKey('pi_home_btn')),
        _menu('テレビ電話', onCall),
        _menu('一斉呼出し', onGroupCall),
        if (hasVideo)
          _menu(
            videoPlaying ? '閉じる' : 'ビデオ',
            onVideo,
            focusNode: videoFocusNode,
            buttonKey: const ValueKey('pi_video_btn'),
          ),
        _menu('健康管理', onHealth),
        _menu('広報配信', onInfo),
        _menu('時計モード', onClock),
        Padding(
          padding: const EdgeInsets.only(bottom: _gap),
          child: Row(
            children: [
              Expanded(
                child: TvPiFocusButton(
                  focusNode: ringFocusNode,
                  label: ring.userEnabled ? '停止' : 'Ring',
                  onPressed: onRing,
                  color: ring.userEnabled
                      ? const Color(0xFFC97187)
                      : const Color(0xFF404040),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  labelOffset:
                      ring.userEnabled ? Offset.zero : const Offset(0, 5),
                ),
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: TvPiFocusButton(
                  focusNode: checkmeFocusNode,
                  label: pro.userEnabled ? '停止' : 'Checkme',
                  onPressed: onCheckme,
                  fontSize: 16 * 0.8,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  labelOffset:
                      pro.userEnabled ? Offset.zero : const Offset(0, 5),
                ),
              ),
            ],
          ),
        ),
        _menu('設定', onSetting, color: const Color(0xFFCC3333)),
        if (showNoCamera)
          const Padding(
            padding: EdgeInsets.only(bottom: _gap),
            child: NoCameraBanner(compact: true),
          ),
        Expanded(
          child: showVitals
              ? TvPiVitalTable(
                  name: displayName,
                  bpHigh: bpHigh,
                  bpLow: bpLow,
                  bpPulse: bpPulse,
                  temp: temp,
                  weight: weight,
                  roomTemp: roomTemp,
                  roomHum: roomHum,
                  spo2: spo2Text,
                  pr: prText,
                  hr: _hrText(hr),
                  pi: _piText(pi),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  String _hrText(String fetched) {
    final live = CheckmeProService.instance.hr;
    if (live != null) return '$live';
    return fetched;
  }

  String _piText(String fetched) {
    final proPi = CheckmeProService.instance.pi;
    if (proPi != null) {
      return proPi.toStringAsFixed(1);
    }
    final ringPi = CheckmeRingService.instance.pi;
    if (ringPi != null) return '$ringPi';
    return fetched;
  }

  Widget _menu(String label, VoidCallback onPressed,
      {Color color = const Color(0xFF404040),
      bool autofocus = false,
      FocusNode? focusNode,
      Key? buttonKey}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _gap),
      child: TvPiFocusButton(
        key: buttonKey,
        label: label,
        onPressed: onPressed,
        color: color,
        autofocus: autofocus,
        focusNode: focusNode,
        padding: const EdgeInsets.symmetric(vertical: 6),
      ),
    );
  }
}

/// ラズパイ版バイタル表。ホーム右下と通話中サイドで共用。
class TvPiVitalTable extends StatelessWidget {
  const TvPiVitalTable({
    super.key,
    required this.name,
    required this.bpHigh,
    required this.bpLow,
    required this.bpPulse,
    required this.temp,
    required this.weight,
    required this.roomTemp,
    required this.roomHum,
    required this.spo2,
    required this.pr,
    this.hr = '-',
    this.pi = '-',
  });

  final String name;
  final String bpHigh;
  final String bpLow;
  final String bpPulse;
  final String temp;
  final String weight;
  final String roomTemp;
  final String roomHum;
  final String spo2;
  final String pr;
  final String hr;
  final String pi;

  @override
  Widget build(BuildContext context) {
    // データ未取得（'-' や空）の項目は行ごと出さない。
    bool has(String v) {
      final t = v.trim();
      return t.isNotEmpty && t != '-' && t != 'null';
    }

    final rows = <_VitalRow>[
      _VitalRow('最高血圧', bpHigh, false),
      _VitalRow('最低血圧', bpLow, false),
      _VitalRow('脈拍(分)', bpPulse, false),
      _VitalRow('体温℃', temp, false),
      _VitalRow('体重 kg', weight, false),
      _VitalRow('室内温度', roomTemp, true),
      _VitalRow('室内湿度', roomHum, true),
      _VitalRow('HR/min', hr, true),
      _VitalRow('SPO2(%)', spo2, true),
      _VitalRow('PRbpm', pr, true),
      _VitalRow('PI', pi, true),
    ].where((r) => has(r.value)).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        // 1行の高さは全11項目ぶんを基準にして一定に保ち（行が減っても
        // 文字サイズが変わらない）、枠自体は表示している行数ぶんに縮める。
        const maxRows = 11;
        final rowH = constraints.maxHeight / (maxRows + 1);
        final bodySize = ((rowH * 0.72).clamp(10.0, 14.0) * 1.2);
        final nameSize = 15.0 * 0.85;
        Widget row(String label, String value, {bool green = false}) {
          return SizedBox(
            height: rowH,
            child: ColoredBox(
              color: green ? const Color(0x8018B55B) : Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  // ラベルと数値の縦位置を揃える（数値だけ上にずれるのを防ぐ）。
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: bodySize,
                          height: 1.05,
                        ),
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: bodySize,
                        fontWeight: FontWeight.bold,
                        height: 1.05,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // 与えられた高さいっぱいに広げず、行数ぶんの高さの枠を上寄せで置く。
        return Align(
          alignment: Alignment.topCenter,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0x804E4E4E),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF999999)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              // 表示行数ぶんの高さに収める（残りは余白にせず枠を短くする）。
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: rowH,
                  child: Center(
                    child: Text(
                      '$name 様',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: nameSize,
                        fontWeight: FontWeight.bold,
                        height: 1.05,
                      ),
                    ),
                  ),
                ),
                for (final item in rows)
                  row(item.label, item.value, green: item.green),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VitalRow {
  const _VitalRow(this.label, this.value, this.green);
  final String label;
  final String value;
  final bool green;
}

/// 未移植機能の仮画面。
class TvComingSoonPage extends StatelessWidget {
  const TvComingSoonPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF222222),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Text(
          '$title はこれから移植します',
          style: const TextStyle(color: Colors.white, fontSize: 28),
        ),
      ),
    );
  }
}
