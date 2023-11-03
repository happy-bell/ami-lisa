import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../appdefine.dart';
import '../../services/appmanager.dart';

class StaffWebPage extends StatefulWidget {
  final String title;
  final String sensorType;
  final String targetId;
  final String targetName;
  StaffWebPage({required this.title, required this.sensorType, required this.targetId, required this.targetName});

  @override
  _StaffWebPageState createState() => _StaffWebPageState();
}

class _StaffWebPageState extends State<StaffWebPage> {
  late WebViewController _controller;
  var _sensorType = '1';
  var _isNext = false;
  var _isTitleBar = true;
  var _url = '';

  @override
  void initState() {
    super.initState();
    print('staffweb initState');
    _sensorType = widget.sensorType;
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();
    print('staff didChangeDependencies');

    var cnt = 0;
    if (AppManager.appsettings['SENSOR1'] == '1') {
      cnt++;
    }
    if (AppManager.appsettings['SENSOR2'] == '1') {
      cnt++;
    }
    if (AppManager.appsettings['SENSOR3'] == '1') {
      cnt++;
    }
    if (AppManager.appsettings['SENSOR4'] == '1') {
      cnt++;
    }
    if (cnt > 1) {
      _isNext = true;
    }
    if (_sensorType == '8'  || _sensorType == '9') {
      _isNext = false;
      _isTitleBar = false;
    }

    setState(() {
      _url = _graphurl();
    });
  }

  void _nextSensorType() {
    if (_sensorType == '1') {
      if (AppManager.appsettings['SENSOR2'] == '1') {
        _sensorType = '2';
        return;
      }
      if (AppManager.appsettings['SENSOR3'] == '1') {
        _sensorType = '3';
        return;
      }
      if (AppManager.appsettings['SENSOR4'] == '1') {
        _sensorType = '4';
        return;
      }
    }
    if (_sensorType == '2') {
      if (AppManager.appsettings['SENSOR3'] == '1') {
        _sensorType = '3';
        return;
      }
      if (AppManager.appsettings['SENSOR4'] == '1') {
        _sensorType = '4';
        return;
      }
      if (AppManager.appsettings['SENSOR1'] == '1') {
        _sensorType = '1';
        return;
      }
    }
    if (_sensorType == '3') {
      if (AppManager.appsettings['SENSOR4'] == '1') {
        _sensorType = '4';
        return;
      }
      if (AppManager.appsettings['SENSOR1'] == '1') {
        _sensorType = '1';
        return;
      }
      if (AppManager.appsettings['SENSOR2'] == '1') {
        _sensorType = '2';
        return;
      }
    }
  }

  Future<void> _nextGraph() async {
    _nextSensorType();
    var url = _graphurl();
    print(url);
    await _controller.loadUrl(url);
  }

  String _graphurl() {
    var cd = AppManager.delegatorCode;
    var id = widget.targetId;
    var name = widget.targetName;
    if (_sensorType == '1') {
      return AppDefine.mcsaURL + "app/legame/" + (AppDefine.amiApp ? "ami.php" : "") + "?cd=$cd&id=$id&na=$name";
    }
    if (_sensorType == '2') {
      return AppDefine.mcsaURL + "pir/" + (AppDefine.amiApp ? "ami.php" : "") + "?cd=$cd&udid=$id&name=$name&src=mntn2";
    }
    if (_sensorType == '3') {
      return AppDefine.mcsaURL + "flame/" + (AppDefine.amiApp ? "ami.php" : "") + "?cd=$cd&udid=$id&uname=$name&src=mntn2";
    }
    if (_sensorType == '4') {
      // return AppDefine.baseURL + "co2sensor/?cd=aop089EU&udid=R005&view=1";
      return AppDefine.mcsaURL + "co2sensor/" + (AppDefine.amiApp ? "ami.php" : "") + "?cd=$cd&udid=$id";
    }
    if (_sensorType == '8') {
      return AppDefine.baseURL + "measurement_result/?code=$cd&mst_id=$id&ua=fl";
    }
    if (_sensorType == '9') {
      return AppDefine.baseURL + "measurement_result/spo2-co2?code=$cd&mst_id=$id&ua=fl";
    }

    return '';
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> actions = [];
    if (_isNext) {
      actions.add(IconButton(
        icon: Image.asset('assets/images/service/sensor_page.png'),
        tooltip: '次のグラフ',
        onPressed: () {
          _nextGraph();
        },
      ));
    }

    return Scaffold(
      appBar: _isTitleBar ? AppBar(
        title: Text(widget.title),
        actions: actions,
      ) : null,
      body: Builder(builder: (BuildContext context) {
        return _url == ''
            ? Container(
          color: Colors.grey.withOpacity(0.3),
          width: MediaQuery.of(context).size.width, //70.0,
          height: MediaQuery.of(context).size.height, //70.0,
          child: const Padding(
              padding: EdgeInsets.all(5.0),
              child: Center(child: CircularProgressIndicator())),
        )
            : SafeArea(
              child: Stack(
          children: [
              WebView(
                initialUrl: _url,
                javascriptMode: JavascriptMode.unrestricted,
                javascriptChannels: {
                  JavascriptChannel(
                    name: 'flutterApp', // 任意の文字列（JS側の呼び出し名になる）
                    onMessageReceived: (result) async {
                      print('flutterApp');

                      Navigator.of(context).pop();
                    },
                  )
                },
                onWebViewCreated: (WebViewController webViewController) {
                  _controller = webViewController;
                },
                onPageFinished: (value) {
                  setState(() {
                    print("====your page is load");
                  });
                },
              ),
          ],
        ),
            );
      }),
    );
  }
}
