import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/widgets/tv_focusable.dart';

class SettingInfoPhotoPage extends StatefulWidget {
  const SettingInfoPhotoPage({super.key});

  @override
  SettingInfoPhotoPageState createState() => SettingInfoPhotoPageState();
}

class SettingInfoPhotoPageState extends State<SettingInfoPhotoPage> {
  bool _loading = true;
  List<dynamic> _data = [];

  String get _code {
    if (AppManager.isManager && AppManager.selectCode.isNotEmpty) {
      return AppManager.selectCode;
    }
    if (AppManager.delegatorCode.isNotEmpty) {
      return AppManager.delegatorCode;
    }
    return (AppManager.settings['DELEGATORCODE'] ??
            AppManager.settings['delegatorcode'] ??
            '')
        .toString();
  }

  @override
  void initState() {
    super.initState();
    Future(() {
      _getData();
    });
  }

  Future<void> _getData() async {
    setState(() {
      _loading = true;
    });

    final dio = Dio();
    var url =
        '${AppDefine.baseURL}elan/api/info_photo_list?code=$_code&token=${AppManager.settings['api_token']}';

    var data = await dio.get(url).then((response) {
      return response.data;
    }).catchError((err) {
      print(err);
      return null;
    });

    if (!mounted) return;
    setState(() {
      _loading = false;
    });

    if (data == null || data is! Map) {
      return;
    }

    setState(() {
      _data = data['list'] is List ? data['list'] : [];
    });
  }

  Future<void> _delete(String itemId) async {
    setState(() {
      _loading = true;
    });
    FormData formData = FormData.fromMap({
      "code": _code,
      "token": AppManager.settings["api_token"],
      "id": itemId,
    });
    var url = '${AppDefine.baseURL}app/delete_info_videos';
    var dio = Dio();
    var data = await dio.post(
      url,
      data: formData,
    ).then((response) {
      print(response.data);
      if (response.data['status'] == 'ok') {
        return response.data;
      }
      return null;
    }).catchError((err) {
      return null;
    });
    if (data == null) {
      _showDialog("削除できませんでした");
    }
    await _getData();
  }

  Future<void> _toggleSelect(itemId) async {
    setState(() {
      _loading = true;
    });
    FormData formData = FormData.fromMap({
      "code": _code,
      "token": AppManager.settings["api_token"],
      "id": itemId,
    });
    var url = "${AppDefine.baseURL}elan/api/info_photo_sel";

    final dio = Dio();
    var data = await dio.post(url, data: formData).then((response) {
      return response.data;
    }).catchError((err) {
      print(err);
      return null;
    });

    print(data);

    if (data != null && data['status'].toString() == 'ok') {
      final index =
          _data.indexWhere((item) => item['id'].toString() == itemId.toString());
      if (index >= 0) {
        _data[index]['sel'] = data['sel'];
      }
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _showDialog(String message) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('確認'),
          content: Text(message),
          actions: <Widget>[
            TvDialogAction(
              autofocus: true,
              label: 'OK',
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<bool> _confirmDelete() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('確認'),
          content: const Text('削除しますか'),
          actions: [
            TvDialogAction(
              autofocus: true,
              label: 'いいえ',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TvDialogAction(
              label: 'はい',
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Widget _listContainer(int index) {
    final item = _data[index];
    final itemId = item['id'].toString();
    final selected = item['sel'].toString() == '1';

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color.fromARGB(255, 220, 220, 220)),
          ),
        ),
        height: TvUtil.isTelevision ? 64 : WidgetUtil.listHeight,
        padding: const EdgeInsets.all(10.0),
        child: Row(
          children: [
            Expanded(
              child: WidgetUtil.basicText(
                item['name']?.toString() ?? '',
                fontSize: TvUtil.isTelevision ? 22 : 14,
              ),
            ),
            if (selected)
              const Icon(
                Icons.check,
                color: Colors.blueAccent,
                size: 24.0,
              ),
            TvFocusable(
              onPressed: () async {
                if (await _confirmDelete()) {
                  await _delete(itemId);
                }
              },
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.delete_outline, color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );

    return TvSettingFocus(
      autofocus: index == 0,
      onActivate: () {
        _toggleSelect(itemId);
      },
      child: row,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: WidgetUtil.appBar(
        'スライドショー',
        backgroundColor: WidgetUtil.iosNavbarBG,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView.builder(
              itemBuilder: (BuildContext context, int index) {
                return _listContainer(index);
              },
              itemCount: _data.length,
            ),
            if (_loading) WidgetUtil.loadingIndicator,
          ],
        ),
      ),
    );
  }
}
