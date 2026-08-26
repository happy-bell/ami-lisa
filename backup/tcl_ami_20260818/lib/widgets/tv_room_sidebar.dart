import 'package:amiapp/services/checkme_ring_service.dart';
import 'package:amiapp/widgets/tv_focusable.dart';
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
    this.bpHigh = '-',
    this.bpLow = '-',
    this.bpPulse = '-',
    this.temp = '-',
    this.weight = '-',
    this.roomTemp = '-',
    this.roomHum = '-',
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
  final String bpHigh;
  final String bpLow;
  final String bpPulse;
  final String temp;
  final String weight;
  final String roomTemp;
  final String roomHum;

  @override
  Widget build(BuildContext context) {
    final ring = CheckmeRingService.instance;
    final spo2 = ring.spo2?.toString() ?? '-';
    final pr = ring.pulse?.toString() ?? '-';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _menu('ホーム', onHome, autofocus: true),
        _menu('テレビ電話', onCall),
        _menu('一斉呼出し', onGroupCall),
        if (hasVideo) _menu(videoPlaying ? '停止' : 'ビデオ', onVideo),
        _menu('健康管理', onHealth),
        _menu('お知らせ', onInfo),
        _menu('時計モード', onClock),
        _menu('設定', onSetting, color: const Color(0xFFCC3333)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _deviceBtn(
                'Ring',
                onRing,
                active: ring.measuring,
                activeColor: const Color(0xFFC97187),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _deviceBtn('Checkme', onCheckme),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _vitalTable(
          name: displayName,
          bpHigh: bpHigh,
          bpLow: bpLow,
          bpPulse: bpPulse,
          temp: temp,
          weight: weight,
          roomTemp: roomTemp,
          roomHum: roomHum,
          spo2: spo2,
          pr: pr,
        ),
      ],
    );
  }

  Widget _menu(String label, VoidCallback onPressed,
      {Color color = const Color(0xFF404040), bool autofocus = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: TvFocusable(
        autofocus: autofocus,
        borderRadius: 20,
        onPressed: onPressed,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF999999)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _deviceBtn(String label, VoidCallback onPressed,
      {bool active = false, Color activeColor = const Color(0xFF404040)}) {
    return TvFocusable(
      borderRadius: 28,
      onPressed: onPressed,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: active ? activeColor : const Color(0xFF404040),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF999999)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _vitalTable({
    required String name,
    required String bpHigh,
    required String bpLow,
    required String bpPulse,
    required String temp,
    required String weight,
    required String roomTemp,
    required String roomHum,
    required String spo2,
    required String pr,
  }) {
    Widget row(String label, String value, {bool green = false}) {
      return Container(
        color: green ? const Color(0x8018B55B) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, height: 1.15),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                height: 1.15,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0x804E4E4E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF999999)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 3),
            alignment: Alignment.center,
            child: Text(
              '$name 様',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          row('最高血圧', bpHigh),
          row('最低血圧', bpLow),
          row('脈拍(分)', bpPulse),
          row('体温℃', temp),
          row('体重 kg', weight),
          row('室内温度', roomTemp, green: true),
          row('室内湿度', roomHum, green: true),
          row('SPO2(%)', spo2, green: true),
          row('PRbpm', pr, green: true),
        ],
      ),
    );
  }
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
