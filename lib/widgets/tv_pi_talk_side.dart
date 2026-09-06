import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/services/and_vital_service.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/checkme_pro_service.dart';
import 'package:amiapp/services/checkme_ring_service.dart';
import 'package:amiapp/services/tv_pi_checkme_share.dart';
import 'package:amiapp/services/tv_pi_talk_vital_sync.dart';
import 'package:amiapp/services/tv_pi_vitals.dart';
import 'package:amiapp/widgets/and_vital_result_popup.dart';
import 'package:amiapp/widgets/checkme_monitor_panel.dart';
import 'package:amiapp/widgets/tv_pi_focus_button.dart';
import 'package:amiapp/widgets/tv_pi_spo2_popup.dart';

/// ラズパイ版通話中の右列（通話終了・Ring/Checkme・自分映像・バイタル）。
class TvPiTalkSide extends StatefulWidget {
  const TvPiTalkSide({
    super.key,
    required this.localRenderer,
    required this.talking,
    required this.isRecording,
    required this.videoMute,
    required this.onHangup,
    this.showLocal = false,
  });

  final RTCVideoRenderer localRenderer;
  final bool talking;
  final bool isRecording;
  final bool videoMute;
  final VoidCallback onHangup;

  /// 自分の映像をこの列に出すか。
  /// 二者通話では通話終了ボタンの下に、三者通話では画面中央上に置く。
  final bool showLocal;

  @override
  State<TvPiTalkSide> createState() => _TvPiTalkSideState();
}

class _TvPiTalkSideState extends State<TvPiTalkSide> {
  final _sync = TvPiTalkVitalSync.instance;

  @override
  void initState() {
    super.initState();
    _sync.addListener(_onChanged);
    CheckmeRingService.instance.addListener(_onChanged);
    CheckmeProService.instance.addListener(_onChanged);
    AndVitalService.instance.addListener(_onChanged);
    CheckmeShareView.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    _sync.removeListener(_onChanged);
    CheckmeRingService.instance.removeListener(_onChanged);
    CheckmeProService.instance.removeListener(_onChanged);
    AndVitalService.instance.removeListener(_onChanged);
    CheckmeShareView.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }



  @override
  Widget build(BuildContext context) {
    // 通話中は「通話終了」だけを出す。画面を占領しないよう、
    // 高さは中身のぶんだけにして、相手の映像を隠さないようにする。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.isRecording || widget.videoMute) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (widget.videoMute)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.videocam_off,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              if (widget.isRecording)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.fiber_manual_record,
                    color: Color(0xFFE53935),
                    size: 28,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        TvPiFocusButton(
          label: '通話終了',
          autofocus: TvUtil.isTelevision,
          onPressed: widget.onHangup,
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        // 通話終了の直下に Ring / Checkme を横並びで置く。
        //
        // ドクターモードのときは、押すと**相手の機器**が動く。
        // 自分の機器は動かない。患者側は自分の機器を動かす。
        // どちらを操作するかは TvPiTalkVitalSync が決める。
        if (widget.talking) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TvPiFocusButton(
                  label: _sync.ringButtonOn ? '停止' : 'Ring',
                  onPressed: _sync.onRingPressed,
                  color: _sync.ringButtonOn
                      ? const Color(0xFFC97187)
                      : const Color(0xFF404040),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: TvPiFocusButton(
                  label: _sync.checkmeButtonOn ? '停止' : 'Checkme',
                  onPressed: _sync.onCheckmePressed,
                  color: _sync.checkmeButtonOn
                      ? const Color(0xFFC97187)
                      : const Color(0xFF404040),
                  fontSize: 16 * 0.8,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ],
          ),
        ],
        if (widget.talking && widget.showLocal) ...[
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 4 / 3,
            child: RTCVideoView(
              widget.localRenderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
        ],
      ],
    );
  }
}

/// 通話中の Ring / Checkme / A&D オーバーレイ。
/// Checkme 開始は [TvPiTalkSide] 側の rebuild だけでは親 Stack に届かないため、
/// ここでも同じサービスを listen してグラフを出す。
class TvPiTalkMeasureOverlays extends StatefulWidget {
  const TvPiTalkMeasureOverlays({super.key, required this.screenSize});

  final Size screenSize;

  @override
  State<TvPiTalkMeasureOverlays> createState() =>
      _TvPiTalkMeasureOverlaysState();
}

class _TvPiTalkMeasureOverlaysState extends State<TvPiTalkMeasureOverlays> {
  @override
  void initState() {
    super.initState();
    TvPiTalkVitalSync.instance.addListener(_onChanged);
    CheckmeProService.instance.addListener(_onChanged);
    CheckmeShareView.instance.addListener(_onChanged);
    CheckmeRingService.instance.addListener(_onChanged);
    AndVitalService.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    TvPiTalkVitalSync.instance.removeListener(_onChanged);
    CheckmeProService.instance.removeListener(_onChanged);
    CheckmeShareView.instance.removeListener(_onChanged);
    CheckmeRingService.instance.removeListener(_onChanged);
    AndVitalService.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sync = TvPiTalkVitalSync.instance;
    final share = CheckmeShareView.instance;
    final pro = CheckmeProService.instance;
    final showGraph = pro.userEnabled || share.active;
    final showSpo2 = sync.spo2PopupVisible;
    final showAnd = AndVitalService.instance.popupVisible && !showSpo2;

    return IgnorePointer(
      child: Stack(
        children: [
          if (showGraph)
            Positioned(
              left: 5,
              bottom: 5,
              width: widget.screenSize.width * 0.43 * 5 / 4,
              height: widget.screenSize.width * 0.43 * 9 / 16,
              child: const IgnorePointer(child: CheckmeMonitorPanel()),
            ),
          if (showSpo2)
            Positioned(
              right: TvPiSpo2Popup.rightInset(widget.screenSize.width * 0.15),
              bottom: TvPiSpo2Popup.bottomInset(),
              child: IgnorePointer(
                child: TvPiSpo2Popup(
                  spo2: sync.spo2Text,
                  pr: sync.prText,
                ),
              ),
            )
          else if (showAnd)
            Positioned(
              right: TvPiSpo2Popup.rightInset(widget.screenSize.width * 0.15),
              top: widget.screenSize.height * 0.22,
              child: const IgnorePointer(child: AndVitalResultPopup()),
            ),
        ],
      ),
    );
  }
}
