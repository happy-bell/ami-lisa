import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/widget_util.dart';
import '../../services/appmanager.dart';

class StaffAlbumPage extends StatefulWidget {
  @override
  State<StaffAlbumPage> createState() => StaffAlbumPageState();
}

class StaffAlbumPageState extends State<StaffAlbumPage> {
  List<FileSystemEntity> files = [];
  var _selectIndex = -1;
  var _selecting = false;
  final List<int> _selectImages = [];
  TextStyle titleTextStyle2 = const TextStyle(fontSize: 14, color: Colors.blue);

  @override
  void initState() {
    super.initState();
    // WidgetsBinding.instance.addObserver(this);
    print('album initState');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    print('album didChangeDependencies');
    _getFiles();
  }

  Future<void> _getFiles() async {
    var docDir = await getApplicationDocumentsDirectory();
    String directory = "${docDir.path}/album/${AppManager.selectUser!.id}";
    Directory("$directory/").exists().then((isThere) {
      if (isThere) {
        setState(() {
          files = Directory("$directory/").listSync();
        });
        print(files);
      } else {
        print('no exists $directory');
      }
    });
  }

  String fileDate(String path) {
    var arr = path.split('/');
    String name =
    arr[arr.length - 1].replaceAll('.png', '').replaceAll('.jpg', '');
    var dateString = name.substring(0, 4) +
        "/" +
        name.substring(4, 6) +
        "/" +
        name.substring(6, 8) +
        " " +
        name.substring(8, 10) +
        ":" +
        name.substring(10, 12);

    return dateString;
  }

  void _selectImage(int index) {
    if (_selecting) {
      if (_selectImages.contains(index)) {
        _selectImages.remove(index);
      } else {
        _selectImages.add(index);
      }
    } else {
      _selectIndex = index;
    }
    setState(() {});
  }

  void _deleteButton() async {
    if (_selectIndex < 0 && !_selecting) {
      return;
    }

    var value = await showDialog(
      context: context,
      builder: (BuildContext context) => new AlertDialog(
        title: new Text('確認'),
        content: new Text('画像を削除しますか？'),
        actions: <Widget>[
          new SimpleDialogOption(
            child: new Text('はい'),
            onPressed: () {
              Navigator.pop(context, "1");
            },
          ),
          new SimpleDialogOption(
            child: new Text('いいえ'),
            onPressed: () {
              Navigator.pop(context, "0");
            },
          ),
        ],
      ),
    );
    switch (value) {
      case "1":
        _delete();
        break;
      case "0":
        break;
    }
  }

  void _delete() {
    if (_selectIndex >= 0) {
      _deleteSelectIndex();
    } else if (_selecting) {
      _deleteSelectImages();
    }
  }

  void _deleteSelectIndex() {
    var file = files[_selectIndex];
    var upFile = File(file.path);
    upFile.deleteSync();
    _selectIndex = -1;
    _getFiles();
  }

  void _deleteSelectImages() {
    _selectImages.forEach((index) {
      var file = files[index];
      var upFile = File(file.path);
      upFile.deleteSync();
    });
    _selectImages.clear();
    _getFiles();
  }

  void _uploadButton() async {
    if (_selectIndex < 0 && !_selecting) {
      return;
    }
    var value = await showDialog(
      context: context,
      builder: (BuildContext context) => new AlertDialog(
        title: new Text('確認'),
        content: new Text('アップロードしますか？'),
        actions: <Widget>[
          new SimpleDialogOption(
            child: new Text('はい'),
            onPressed: () {
              Navigator.pop(context, "1");
            },
          ),
          new SimpleDialogOption(
            child: new Text('いいえ'),
            onPressed: () {
              Navigator.pop(context, "0");
            },
          ),
        ],
      ),
    );
    switch (value) {
      case "1":
        if (_selectIndex >= 0) {
          _uploadSelectIndex();
        } else if (_selecting) {
          _uploadSelectImages();
        }
        break;
      case "0":
        break;
    }
  }

  String _uploadURL() {
    if (AppDefine.amiApp) {
      return AppDefine.baseURL + 'app/upload_photos';
    }
    return AppDefine.baseURL + "app/upphototest.php";
  }

  void _uploadSelectIndex() async {
    var file = files[_selectIndex];
    String fileName = file.path.split('/').last;
    FormData formData = FormData.fromMap({
      "mcs": AppManager.settings["MCSURL"],
      "gcd": AppManager.settings["MCSGROUPCODE"],
      "ccd": AppManager.settings["MCSCLINICCODE"],
      "mid": AppManager.selectUser!.id,
      "code": AppManager.settings["DELEGATORCODE"],
      "mst_id": AppManager.selectUser!.id.replaceAll(AppManager.settings["DELEGATORCODE"] + "_", ""),
      "files0": await MultipartFile.fromFile(file.path, filename: fileName),
    });
    var url = _uploadURL();
    var dio = Dio();
    try {
      var response = await dio.post(url, data: formData);
      _showDialog("アップロードしました");
    } catch (e) {
      _showDialog("アップロードできませんでした");
    }
  }

  void _uploadSelectImages() async {
    Map<String, dynamic> formDataMap = {
      "mcs": AppManager.settings["MCSURL"],
      "gcd": AppManager.settings["MCSGROUPCODE"],
      "ccd": AppManager.settings["MCSCLINICCODE"],
      "mid": AppManager.selectUser!.id,
    };
    var fileNo = 0;
    await Future.forEach(_selectImages, (index) async {
      var file = files[index];
      String fileName = file.path.split('/').last;
      formDataMap["files" + fileNo.toString()] = await MultipartFile.fromFile(file.path, filename: fileName);
      fileNo++;
    });
    print(formDataMap);
    FormData formData = FormData.fromMap(formDataMap);
    var url = AppDefine.baseURL + "app/upphototest.php";
    var dio = Dio();
    try {
      var response = await dio.post(url, data: formData);
      print(response);
      _showDialog("アップロードしました");
    } catch (e) {
      _showDialog("アップロードできませんでした");
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    const bottomHeight = 50.0;
    var cols = size.width > 600 ? 4 : 2;
    var smallButtonSize = 32.0;

    List<Widget> actions = [];
    if (_selectIndex < 0) {
      actions.add(InkWell(
        onTap: () {
          setState(() {
            _selecting = !_selecting;
          });
          _selectImages.clear();
        },
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              _selecting ? 'キャンセル' : '選択',
              style: titleTextStyle2,
            ),
          ),
        ),
      ));
    }

    return Scaffold(
      appBar: WidgetUtil.appBar(AppManager.selectUser!.name,
        backgroundColor: WidgetUtil.iosNavbarBG,
        foregroundColor: Colors.black,
        actions: actions,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 8.0,
            bottom: bottomHeight,
            left: 4.0,
            width: size.width - 8.0,
            child: GridView.builder(
              itemBuilder: (BuildContext context, int index) {
                return GestureDetector(
                  onTap: () {
                    _selectImage(index);
                  },
                  child: Container(
                    // color: Color.fromARGB(255, 240, 240, 240),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(File(files[index].path), fit: BoxFit.cover),
                          Positioned(
                            bottom: 2.0,
                            height: 20.0,
                            width: size.width / cols - 8,
                            child: Center(
                              child: Text(fileDate(files[index].path)),
                            ),
                          ),
                          if (_selecting)
                            Positioned(
                              top: 4.0,
                              right: 4.0,
                              width: 24,
                              height: 24,
                              child: _selectImages.contains(index)
                                  ? const Icon(Icons.check_circle, color: Colors.blue)
                                  : const Icon(Icons.radio_button_unchecked, color: Colors.blue),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              itemCount: files.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio: size.width / size.height,
                mainAxisSpacing: 8.0,
                crossAxisSpacing: 8.0,
              ),
            ),
          ),
          if (_selectIndex >= 0)
            Positioned(
              top: 0,
              bottom: bottomHeight,
              left: 0,
              width: size.width,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectIndex = -1;
                  });
                },
                child: ColoredBox(
                  color: Colors.grey,
                  child: Image.file(File(files[_selectIndex].path)),
                ),
              ),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            width: size.width,
            height: bottomHeight,
            // right: constraints.maxWidth,
            child: Container(
              decoration: BoxDecoration(
                color: Color.fromARGB(255, 248, 248, 248),
                border: new Border(
                  top:
                  new BorderSide(color: Color.fromARGB(255, 220, 220, 220)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: IconButton(
                      icon: Icon(
                        Icons.delete,
                        color: (_selectIndex < 0 && !_selecting)
                            ? Colors.grey
                            : Colors.blue,
                        size: 32,
                      ),
                      onPressed: () {
                        if (_selectIndex >= 0 || _selecting) {
                          _deleteButton();
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.publish,
                      color: (_selectIndex < 0 && !_selecting)
                          ? Colors.grey
                          : Colors.blue,
                      size: 32,
                    ),
                    onPressed: () {
                      if (_selectIndex >= 0 || _selecting) {
                        _uploadButton();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future _showDialog(String message) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("確認"),
          content: Text(message),
          actions: <Widget>[
            SimpleDialogOption(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}