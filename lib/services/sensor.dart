import 'dart:async';
import 'package:dio/dio.dart';

import '../appdefine.dart';
import 'appmanager.dart';

mixin SensorServiceDelegate {
  void onSensorAlertsChange();
}

class SensorService {
  // static SensorService _instance = SensorService._internal();

  bool load = false;
  String sensorTime1 = "";
  String sensorTime2 = "";
  String sensorTime3 = "";
  String sensorTime5 = "";
  Map<String, String> noneTimes = {};
  Map<String, String> flameAlertTimes = {};

  Map<String, String> alerts = {};
  Map<String, List<dynamic>> biosilverAlerts = {};
  Timer? _timer;
  SensorServiceDelegate? delegate;

  // SensorService._internal();

  // factory SensorService() {
  //   if (_instance == null) {
  //     _instance = SensorService._internal();
  //   }
  //   return _instance;
  // }

  void startWatch() {
    _timer = Timer.periodic(const Duration(milliseconds: 3000), (Timer timer) {
      _watch();
    });
  }

  void stopWatch() {
    if (_timer != null) {
      if (_timer!.isActive) {
        _timer!.cancel();
      }
      _timer = null;
    }
    alerts = {};
    noneTimes = {};
  }

  Future<void> _watch() async {
    if (load) {
      return;
    }
    load = true;
    bool isChange = false;
    if (AppManager.appsettings['SENSOR1'] == '1') {
      bool change1 = await _requestLegame();
      if (change1) {
        isChange = true;
      }
    }
    if (AppManager.appsettings['SENSOR2'] == '1') {
      bool change2 = await _requestPir();
      if (change2) {
        isChange = true;
      }
      print(change2);
      print(alerts);
    }
    if (AppManager.appsettings['SENSOR3'] == '1') {
      bool change3 = await _requestFlame();
      if (change3) {
        isChange = true;
      }
    }
    if (AppManager.appsettings['SENSOR5'] == '1') {
      bool change5 = await _requestBiosilver();
      if (change5) {
        isChange = true;
      }
    }

    if (isChange) {
      delegate?.onSensorAlertsChange();
    }

    load = false;
  }

  void clearAlert(String udid) {
    if (alerts[udid] != null) {
      alerts.remove(udid);
    }
  }

  Future<bool> _requestLegame() async {
    var url = '${AppDefine.baseURL}app/legame/alert?cd=${AppManager.delegatorCode}&ti=$sensorTime1';
    var dio = Dio();
    try {
      var response = await dio.get(url);
      // print(response.data);
      sensorTime1 = response.data['time'].toString();
      var status = response.data['status'].toString();
      if (status == 'OK') {
        bool isChange = false;
        List values = response.data['values'];
        for (var i = 0; i < values.length; i++) {
          var udid = values[i]['udid'].toString();
          var alert = values[i]['flag'];
          // print('$udid, $tin, $alert');
          if (alerts[udid] == null) {
            alerts[udid] = 'legame_' + alert;
            isChange = true;
          }
        }
        return isChange;
      }
      // var jsonResponse = json.decode(response.data);
      // return jsonResponse;
    } catch (e) {
    }
    return false;
  }

  Future<bool> _requestPir() async {
    var url = '${AppDefine.baseURL}app/pir/alert';

    FormData formData = FormData.fromMap({
      "cd": AppManager.delegatorCode,
      "ti": sensorTime2,
      "tin": noneTimes,
    });
    var dio = Dio();
    try {
      var response = await dio.post(url, data: formData);
      // print(response.data);
      sensorTime2 = response.data['time'].toString();
      var status = response.data['status'].toString();
      if (status == 'OK') {
        bool isChange = false;
        List values = response.data['values'];
        for (var i = 0; i < values.length; i++) {
          var udid = values[i]['udid'].toString();
          var tin = values[i]['tin'].toString();
          var alert = values[i]['alert'];
          // print('$udid, $tin, $alert');
          if (alerts[udid] == null) {
            alerts[udid] = 'pir_' + alert;
            isChange = true;
          }
          if (tin.isNotEmpty) {
            noneTimes[udid] = tin;
          }
        }
        return isChange;
      }
      // var jsonResponse = json.decode(response.data);
      // return jsonResponse;
    } catch (e) {
    }
    return false;
  }

  Future<bool> _requestFlame() async {
    var url = '${AppDefine.baseURL}app/flame/alert';

    FormData formData = FormData.fromMap({
      "cd": AppManager.delegatorCode,
      "ti": sensorTime3,
      "tia": flameAlertTimes,
    });
    var dio = Dio();
    try {
      var response = await dio.post(url, data: formData);
      // print(response.data);
      sensorTime3 = response.data['time'].toString();
      var status = response.data['status'].toString();
      if (status == 'OK') {
        bool isChange = false;
        List values = response.data['values'];
        for (var i = 0; i < values.length; i++) {
          var udid = values[i]['udid'].toString();
          var tin = values[i]['tia'].toString();
          var alert = values[i]['alert'];
          // print('$udid, $tin, $alert');
          if (alerts[udid] == null) {
            alerts[udid] = 'flame';
            isChange = true;
          }
          if (tin.isNotEmpty) {
            flameAlertTimes[udid] = tin;
          }
        }
        return isChange;
      }
      // var jsonResponse = json.decode(response.data);
      // return jsonResponse;
    } catch (e) {
    }
    return false;
  }

  Future<void> resetBiosilver(udid) async {

    var url = '${AppDefine.baseURL}app/biosilver/reset';
    FormData formData = FormData.fromMap({
      "cd": AppManager.delegatorCode,
      "udid": udid,
    });

    var dio = Dio();
    try {
      var response = await dio.post(url, data: formData);
    } catch (e) {
    }
  }

  Future<bool> _requestBiosilver() async {
    var url = '${AppDefine.baseURL}app/biosilver/alert';

    FormData formData = FormData.fromMap({
      "cd": AppManager.delegatorCode,
      "ti": sensorTime5,
    });
    var dio = Dio();
    try {
      var response = await dio.post(url, data: formData);
      print(response.data);
      sensorTime5 = response.data['time'].toString();
      var status = response.data['status'].toString();
      if (status == 'OK') {
        bool isChange = false;
        List values = response.data['values'];
        for (var i = 0; i < values.length; i++) {
          var udid = values[i]['udid'].toString();
          var bioalerts = values[i]['alerts'];
          var isReset = values[i]['isReset'];
          if (isReset == '1') {
            biosilverAlerts.remove(udid);
          }
          print("bioalerts ->");
          print(bioalerts);
          print(bioalerts.length);
          if (bioalerts.length > 0) {
            if (biosilverAlerts.containsKey(udid)) {
              for (var j = 0; j < biosilverAlerts[udid]!.length; j++) {
                if (!bioalerts.contains(biosilverAlerts[udid]![j])) {
                  bioalerts.add(biosilverAlerts[udid]![j]);
                }
              }
            }
            biosilverAlerts[udid] = bioalerts;
            print("biosilverAlerts ->");
            print(biosilverAlerts[udid]);
          }
          isChange = true;
        }
        return isChange;
      }
      // var jsonResponse = json.decode(response.data);
      // return jsonResponse;
    } catch (e) {
    }
    return false;
  }

  static String imageName(String alert) {
    if (alert == 'legame_A') {
      return 'assets/images/sensor/alert_A.png';
    } else if (alert == 'legame_B') {
      return 'assets/images/sensor/alert_B.png';
    } else if (alert == 'legame_H') {
      return 'assets/images/sensor/alert_H.png';
    } else if (alert == 'legame_R') {
      return 'assets/images/sensor/alert_R.png';
    } else if (alert == 'pir_m') {
      return 'assets/images/sensor/pirsensor_zaitaku.png';
    } else if (alert == 'pir_n') {
      return 'assets/images/sensor/pirsensor_none.png';
    } else if (alert == 'pir_p') {
      return 'assets/images/sensor/pirsensor_call.png';
    } else if (alert == 'flame') {
      return 'assets/images/sensor/flame_sensor.png';
    }

    return '';
  }

  static String biosilverImageName(List<dynamic> alerts) {
    if (alerts.isEmpty) {
      return '';
    }

    var flag = alerts[0].toString();
    return 'assets/images/sensor/bs_$flag.png';
  }
}