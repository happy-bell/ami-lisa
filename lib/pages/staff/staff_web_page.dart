import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../appdefine.dart';
import '../../services/appmanager.dart';

class StaffWebPage extends StatefulWidget {
  final String title;
  final String sensorType;
  final String targetId;
  final String targetName;
  const StaffWebPage({
    super.key,
    required this.title,
    required this.sensorType,
    required this.targetId,
    required this.targetName,
  });

  @override
  State<StaffWebPage> createState() => _StaffWebPageState();
}

class _StaffWebPageState extends State<StaffWebPage> {
  late WebViewController _controller;

  /// 現在表示中のセンサー種別
  late String _sensorType;

  /// 複数センサーがあるか
  late final bool _isNext;

  /// タイトルバーを出すか
  bool _isTitleBar = true;

  @override
  void initState() {
    super.initState();
    _sensorType = widget.sensorType;

    // 何種類のグラフを回すか判定
    final sensorFlags = [
      AppManager.appsettings['SENSOR1'],
      AppManager.appsettings['SENSOR2'],
      AppManager.appsettings['SENSOR3'],
      AppManager.appsettings['SENSOR4'],
    ];
    _isNext = sensorFlags.where((e) => e == '1').length > 1;

    if (_sensorType == '8' || _sensorType == '9') {
      _isTitleBar = false; // フルスクリーン
    }

    _initController(); // controller を用意
  }

  /* ---------------- WebViewController を作成 ---------------- */
  void _initController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'flutterApp',
        onMessageReceived: (_) => Navigator.of(context).pop(),
      )
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => setState(() {})),
      )
      ..loadRequest(Uri.parse(_graphUrl()));
  }

  /* ---------------- 次グラフへ ---------------- */
  Future<void> _nextGraph() async {
    final order = ['1', '2', '3', '4'];
    var idx = order.indexOf(_sensorType);
    for (var i = 1; i < order.length; i++) {
      final next = order[(idx + i) % order.length];
      if (AppManager.appsettings['SENSOR$next'] == '1') {
        _sensorType = next;
        break;
      }
    }
    await _controller.loadRequest(Uri.parse(_graphUrl()));
  }

  /* ---------------- URL 生成 ---------------- */
  String _graphUrl() {
    final cd = AppManager.delegatorCode;
    final id = widget.targetId;
    final name = widget.targetName;

    switch (_sensorType) {
      case '1':
        return "${AppDefine.mcsaURL}app/legame/${AppDefine.amiApp ? "ami.php" : ""}?cd=$cd&id=$id&na=$name";
      case '2':
        return "${AppDefine.mcsaURL}pir/${AppDefine.amiApp ? "ami.php" : ""}?cd=$cd&udid=$id&name=$name&src=mntn2";
      case '3':
        return "${AppDefine.mcsaURL}flame/${AppDefine.amiApp ? "ami.php" : ""}?cd=$cd&udid=$id&uname=$name&src=mntn2";
      case '4':
        return "${AppDefine.mcsaURL}co2sensor/${AppDefine.amiApp ? "ami.php" : ""}?cd=$cd&udid=$id";
      case '8':
        return "${AppDefine.baseURL}measurement_result/?code=$cd&mst_id=$id&ua=fl";
      case '9':
        return "${AppDefine.baseURL}measurement_result/spo2-co2?code=$cd&mst_id=$id&ua=fl";
      default:
        return '';
    }
  }

  /* ---------------- 画面 ---------------- */
  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (_isNext)
        IconButton(
          icon: Image.asset('assets/images/service/sensor_page.png'),
          tooltip: '次のグラフ',
          onPressed: _nextGraph,
        ),
    ];

    return Scaffold(
      appBar: _isTitleBar
          ? AppBar(title: Text(widget.title), actions: actions)
          : null,
      body: SafeArea(child: WebViewWidget(controller: _controller)),
    );
  }
}
