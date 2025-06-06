import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/services/appmanager.dart';

class SettingInfoPhotoPage extends StatefulWidget {
  const SettingInfoPhotoPage({super.key});


  @override
  SettingInfoPhotoPageState createState() => SettingInfoPhotoPageState();
}

class SettingInfoPhotoPageState extends State<SettingInfoPhotoPage> {
  bool _loading = true;
  final _init = true;
  List<dynamic> _data = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    print('initstate');

    Future(() {
      print('initstate future');
      _getData();
    });
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();
    print('didChangeDependencies');
  }

  Future<void> _getData() async {
    setState(() {
      _loading = true;
    });

    final dio = Dio();
    var url = '${AppDefine.baseURL}elan/api/info_photo_list?code=${AppManager.settings['DELEGATORCODE']}&token=${AppManager.settings['api_token']}';

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
    });
  }

  Future<void> _upload(String filePath) async {
    setState(() {
      _loading = true;
    });
    final ext = p.extension(filePath, 2);
    var fileName = '${AppManager.dateFormat(DateTime.now(), 'yyyy年MM月dd日HH時mm分')}$ext';
    FormData formData = FormData.fromMap({
      "code": AppManager.delegatorCode,
      "token": AppManager.settings["api_token"],
      "name": fileName,
      "file": await MultipartFile.fromFile(filePath, filename: fileName),
    });
    var url = '${AppDefine.baseURL}elan/api/store_info_photo';
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
    setState(() {
      _loading = false;
    });
    if (data == null) {
      _showDialog("アップロードできませんでした");
    } else {
      _getData();
    }

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

  Future<void> _toggleSelect(itemId) async {
    setState(() {
      _loading = true;
    });
    FormData formData = FormData.fromMap({
      "code": AppManager.delegatorCode,
      "token": AppManager.settings["api_token"],
      "id": itemId,
    });
    var url = "${AppDefine.baseURL}elan/api/info_photo_sel";

    final dio = Dio();
    var data = await dio.post(
      url,
      data: formData
    ).then((response) {
      return response.data;
    }).catchError((err) {
      print(err);
      return null;
    });

    print(data);

    if (data != null) {
      if (data['status'].toString() == 'ok') {
        final index = _data.indexWhere((item) => item['id'].toString() == itemId);
        if (index >= 0) {
          _data[index]['sel'] = data['sel'];
        }
      }
    }

    setState(() {
      _loading = false;
    });

    // _getData();
  }

  Future<void> _showDialog(String message) async {
    var _ = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('確認'),
          content: Text(message),
          actions: <Widget>[
            SimpleDialogOption(
              child: const Text('OK'),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _selectPickPhoto() async {
    const double fontSize = 16;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('画像を選択'),
        actions: <CupertinoActionSheetAction>[
          CupertinoActionSheetAction(
            child: const Text('カメラで撮影', style: TextStyle(fontSize: fontSize),),
            onPressed: () {
              Navigator.of(context).pop();
              _pickImage(ImageSource.camera);
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('写真を選択', style: TextStyle(fontSize: fontSize),),
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

  Future<void> _pickImage(ImageSource source) async {
    final XFile? file = await _picker.pickImage(source: source);
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
            _toggleSelect(item['id'].toString());
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
                if (item['sel'].toString() == '1')
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
    actions.add(TextButton(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontSize: 16),
      ),
      onPressed: _data.length >= 5 ? null : _selectPickPhoto,
      child: const Text('登録'),
    ));

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: WidgetUtil.appBar('スライドショー',
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
