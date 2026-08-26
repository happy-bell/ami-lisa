import 'package:amiapp/services/checkme_pro_service.dart';
import 'package:amiapp/services/checkme_ring_service.dart';

/// Ring と Checkme Pro は BLEアダプタを1つしか使えないため排他する。
/// 46amip4 の Ring開始時に Checkme 停止、Checkme開始時に Ring停止 と同じ。
class BleExclusive {
  static Future<void> toggleRing() async {
    if (CheckmeRingService.instance.userEnabled) {
      await CheckmeRingService.instance.setEnabled(false);
      return;
    }
    await CheckmeProService.instance.setEnabled(false);
    CheckmeRingService.instance.resume();
    await CheckmeRingService.instance.setEnabled(true);
  }

  static Future<void> togglePro() async {
    if (CheckmeProService.instance.userEnabled) {
      await CheckmeProService.instance.setEnabled(false);
      return;
    }
    await CheckmeRingService.instance.setEnabled(false);
    CheckmeProService.instance.resume();
    await CheckmeProService.instance.setEnabled(true);
  }
}
