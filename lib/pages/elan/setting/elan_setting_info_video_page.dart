import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/services/appmanager.dart';

class ElanSettingInfoVideoPage extends StatefulWidget {

  @override
  ElanSettingInfoVideoPageState createState() => ElanSettingInfoVideoPageState();
}

class ElanSettingInfoVideoPageState extends State<ElanSettingInfoVideoPage> {
  bool _loading = false;
  var _init = true;
  List<dynamic> _data = [];
  var _selectId = '';
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    print('setting info video initState');
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();
    print('setting info video didChangeDependencies');

    if (_init) {
      _init = false;
      _getData();
    }

  }

  Future<void> _getData() async {
    setState(() {
      _loading = true;
    });

    final dio = Dio();
    var url = '${AppDefine.baseURL}app/info_video_list?code=${AppManager.settings['DELEGATORCODE']}&token=${AppManager.settings['api_token']}';

    var data = await dio.get(
      url,
    ).then((response) {
      return response.data;
    }).catchError((err) {
      print(err);
      return null;
    });

    setState(() {
      _loading = false;
    });

    if (data == null) {
      return;
    }

    print(data);

    setState(() {
      _data = data['list'];
      _selectId = data['selectId'].toString();
    });
  }

  Future<void> _upload(String filePath) async {
    setState(() {
      _loading = true;
    });
    var fileName = '${AppManager.dateFormat(DateTime.now(), 'yyyy年MM月dd日HH時mm分')}.mp4';
    FormData formData = FormData.fromMap({
      "code": AppManager.delegatorCode,
      "token": AppManager.settings["api_token"],
      "name": fileName,
      "file": await MultipartFile.fromFile(filePath, filename: fileName),
    });
    var url = '${AppDefine.baseURL}app/upload_info_videos';
    var dio = Dio();
    try {
      var response = await dio.post(url, data: formData);
      print(response);
      _getData();
    } catch (e) {
      _showDialog("アップロードできませんでした");
    }
    setState(() {
      _loading = false;
    });
  }

  Future<void> _delete(String itemId) async {
    setState(() {
      _loading = true;
    });
    FormData formData = FormData.fromMap({
      "code": AppManager.delegatorCode,
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
      _getData();
    }
    setState(() {
      _loading = false;
    });
  }

  Future<void> _showDialog(String message) async {
    var _ = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('確認'),
          content: Text(message),
          actions: <Widget>[
            SimpleDialogOption(
              child: Text('OK'),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _selectVideo(id) async {
    setState(() {
      _loading = true;
    });
    var url = "${AppDefine.baseURL}app/info_video_sel?id=$id&code=${AppManager.settings['DELEGATORCODE']}&token=${AppManager.settings['api_token']}";

    final dio = Dio();
    var data = await dio.get(
      url,
    ).then((response) {
      return response.data;
    }).catchError((err) {
      print(err);
      return null;
    });

    print(data);

    if (data != null) {
      if (data['status'].toString() == 'ok') {
        _selectId = id;
      }
    }

    setState(() {
      _loading = false;
    });

    // _getData();
  }

  Future<void> _selectPickVideo() async {
    const double fontSize = 16;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('動画を選択'),
        actions: <CupertinoActionSheetAction>[
          CupertinoActionSheetAction(
            child: const Text('カメラで撮影', style: TextStyle(fontSize: fontSize),),
            onPressed: () {
              Navigator.of(context).pop();
              _pickImage(ImageSource.camera);
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('動画を選択', style: TextStyle(fontSize: fontSize),),
            onPressed: () {
              Navigator.of(context).pop();
              _pickImage(ImageSource.gallery);
            },
          ),
        ],
        cancelButton: CupertinoButton(
          child: const Text("キャンセル", style: TextStyle(color: Colors.red),),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source, {BuildContext? context, bool isMultiImage = false}) async {
    final XFile? file = await _picker.pickVideo(source: source, maxDuration: const Duration(seconds: 300));
    if (file != null) {
      _upload(file.path);
    }
  }

  Widget _listContainer(int index) {
    final item = _data[index];
    final itemId = item['id'].toString();

    return Dismissible(
      key: ObjectKey(_data[index]),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('確認'),
              content: const Text('削除しますか'),
              actions: [
                SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('はい'),
                ),
                SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('いいえ'),
                ),
              ],
            );
          },
        );
      },
      onDismissed: (direction) {
        setState(() {
          _data.removeAt(index);
        });
        _delete(itemId);
      },
      background: Container(
        padding: const EdgeInsets.only(right: 10,),
        alignment: AlignmentDirectional.centerEnd,
        color: Colors.red,
        child: const Icon(
          Icons.delete,
          color: Colors.white,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: InkWell(
          onTap: () {
            _selectVideo(item['id'].toString());
          },
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color.fromARGB(255, 220, 220, 220)),
              ),
            ),
            height: WidgetUtil.listHeight,
            padding: const EdgeInsets.all(10.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                WidgetUtil.basicText(item['name']),
                if (itemId == _selectId)
                  const Icon(
                    Icons.check,
                    color: Colors.blueAccent,
                    size: 24.0,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    List<Widget> actions = [];
    actions.add(IconButton(
      icon: const Icon(Icons.add),
      color: Colors.black,
      tooltip: '登録',
      onPressed: () {
        _selectPickVideo();
      },
    ));

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: WidgetUtil.appBar('お知らせ動画',
        actions: actions,
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
            if (_loading)
              WidgetUtil.loadingIndicator,
          ],
        ),
      ),
    );
  }
}
