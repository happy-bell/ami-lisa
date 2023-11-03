import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:amiapp/pages/elan/setting/elan_crop_image_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/pages/setting/setting_args.dart';
import 'package:amiapp/pages/elan/setting/elan_input_user_name_page.dart';
import 'package:amiapp/services/appmanager.dart';

class ElanUserListPage extends StatefulWidget {

  @override
  ElanUserListPageState createState() => ElanUserListPageState();
}

class ElanUserListPageState extends State<ElanUserListPage> {
  bool _loading = false;
  var title = '';
  var _init = true;
  List<dynamic> _data = [];
  final ImagePicker _picker = ImagePicker();
  dynamic _changeImageUser;
  XFile? _pickedFile;
  CroppedFile? _croppedFile;
  bool _isChange = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();

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
    var url = '${AppDefine.baseURL}elan/api/user_list?token=${AppManager.settings['api_token']}';
    print(url);

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

    // print(data);

    setState(() {
      _data = data['users'];
    });
  }

  Future<void> _selectPickImage(dynamic item) async {
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
              _changeImageUser = item;
              _pickImage(ImageSource.camera);
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('写真を選択', style: TextStyle(fontSize: fontSize),),
            onPressed: () {
              Navigator.of(context).pop();
              _changeImageUser = item;
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

  void _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
      );
      if (pickedFile != null) {
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: pickedFile.path,
          compressFormat: ImageCompressFormat.jpg,
          compressQuality: 100,
          aspectRatio: const CropAspectRatio(ratioX: 4, ratioY: 3),
          uiSettings: [
            AndroidUiSettings(
                toolbarTitle: 'Cropper',
                toolbarColor: Colors.deepOrange,
                toolbarWidgetColor: Colors.white,
                initAspectRatio: CropAspectRatioPreset.original,
                lockAspectRatio: false),
            IOSUiSettings(
              title: 'サイズ指定',
              rotateButtonsHidden: true,
              resetButtonHidden: true,
              aspectRatioPickerButtonHidden: true,
              aspectRatioLockEnabled: true,
              doneButtonTitle: '決定',
              cancelButtonTitle: 'キャンセル',
            ),
          ],
        );
        if (croppedFile != null) {
          _upload(croppedFile.path);
        }
      }
      // if (pickedFile != null) {
      //   _upload(pickedFile.path, item);
      // }
    } catch (e) {
      return;
    }
  }

  Future<void> _upload(String imagePath) async {
    setState(() {
      _loading = true;
    });
    var formData = FormData.fromMap({
      'code': _changeImageUser['code'].toString(),
      'mst_id': _changeImageUser['mst_id'].toString(),
      'token': AppManager.settings['api_token'],
    });
    formData.files.addAll([
      MapEntry("file", await MultipartFile.fromFile(imagePath)),
    ]);
    var url = '${AppDefine.baseURL}elan/api/store_user_image';
    final dio = Dio();
    final data = await dio.post(
      url,
      data: formData,
    ).then((response) {
      print(response.data);

      if (response.data['status'] == 'ok') {
        return response.data;
      }
      return null;
    }).catchError((err) {
      print(err);
      return null;
    });

    if (data != null) {
      _isChange = true;
    }

    setState(() {
      _loading = false;
    });
    _getData();
  }

  Widget _listContainer(int index) {
    var item = _data[index];

    Uint8List bytes = Uint8List(0);
    var imageName = 'assets/images/status/dummy.png';
    if (item['photo'].isNotEmpty) {
      var photo = item['photo'];
      var base64Pos = photo.indexOf('base64,');
      if (base64Pos >= 0) {
        photo = photo.substring(base64Pos + 'base64,'.length);
        bytes = base64Decode(photo);
      }
    }

    Widget imageWidget = Image.asset(
      imageName,
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );
    if (bytes.isNotEmpty) {
      imageWidget = Image.memory(
        bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color.fromARGB(255, 220, 220, 220)),
          ),
        ),
        height: WidgetUtil.listHeight + 20,
        padding: const EdgeInsets.all(10.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: 80,
              child: WidgetUtil.basicText(item['mst_id']),
            ),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: bytes.isNotEmpty ? Colors.transparent : Colors.grey),
              ),
              margin: const EdgeInsets.only(right: 20),
              width: 80,
              child: InkWell(
                onTap: () {
                  _selectPickImage(item);
                },
                child: imageWidget,
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: () async {
                  var result = await Navigator.of(context)
                      .push(MaterialPageRoute(builder: (context) => ElanInputUserNamePage(item: item)));
                  if (result != null) {
                    _isChange = true;
                    _getData();
                  }
                },
                child: WidgetUtil.basicText(item['name']),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    return WillPopScope(
      onWillPop: () {
        Navigator.pop(context, _isChange);
        return Future.value(false);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: WidgetUtil.appBar('利用者名変更',
          backgroundColor: WidgetUtil.iosNavbarBG,
          foregroundColor: Colors.black,
        ),
        body: SafeArea(
          child: Stack(
            children: [
              RefreshIndicator(
                onRefresh: () async {
                  await _getData();
                },
                child: ListView.builder(
                  itemBuilder: (BuildContext context, int index) {
                    return _listContainer(index);
                  },
                  itemCount: _data.length,
                ),
              ),
              if (_loading)
                WidgetUtil.loadingIndicator,
            ],
          ),
        ),
      ),
    );
  }
}
