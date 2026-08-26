import 'package:flutter/foundation.dart';

/// 通話中に相手から届いた Checkme 波形。TCLアミでは使わない。
class CheckmeShareView extends ChangeNotifier {
  CheckmeShareView._();
  static final CheckmeShareView instance = CheckmeShareView._();

  bool active = false;
  int? hr;
  int? spo2;
  int? pr;
  double? pi;
  List<int> ecg = const [];
  List<int> pleth = const [];
  int waveVersion = 0;
  DateTime? lastAt;

  bool get recent {
    final t = lastAt;
    if (t == null) return false;
    return DateTime.now().difference(t).inSeconds < 8;
  }

  void apply({
    int? hr,
    int? spo2,
    int? pr,
    double? pi,
    List<int>? ecg,
    List<int>? pleth,
  }) {
    active = true;
    this.hr = hr;
    this.spo2 = spo2;
    this.pr = pr;
    this.pi = pi;
    if (ecg != null) this.ecg = ecg;
    if (pleth != null) this.pleth = pleth;
    lastAt = DateTime.now();
    waveVersion++;
    notifyListeners();
  }

  void clear() {
    if (!active && hr == null && ecg.isEmpty) return;
    active = false;
    hr = null;
    spo2 = null;
    pr = null;
    pi = null;
    ecg = const [];
    pleth = const [];
    lastAt = null;
    waveVersion++;
    notifyListeners();
  }
}
