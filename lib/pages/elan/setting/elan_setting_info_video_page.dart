import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:amiapp/appdefine.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/widgets/tv_focusable.dart';

class ElanSettingInfoVideoPage extends StatefulWidget {
  const ElanSettingInfoVideoPage({super.key});

  @override
  ElanSettingInfoVideoPageState createState() =>
      ElanSettingInfoVideoPageState();
}

class ElanSettingInfoVideoPageState extends State<ElanSettingInfoVideoPage> {
  bool _loading = false;
  var _init = true;
  List<dynamic> _data = [];
  var _selectId = '';
  var _loop = '0';
  bool _playBusy = false;
  String _infoVideoPath = '';

  Dio _dio() => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 10),
      ));

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
  void didChangeDependencies() {
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
    var url =
        '${AppDefine.baseURL}app/info_video_list?code=$_code&token=${AppManager.settings['api_token']}';

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
      _selectId = (data['selectId'] ?? '').toString();
      _loop = (data['loop'] ?? '0').toString();
    });
    await _refreshInfoPath();
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

  Future<void> _selectVideo(id) async {
    setState(() {
      _loading = true;
    });
    var url =
        "${AppDefine.baseURL}app/info_video_sel?id=$id&code=$_code&token=${AppManager.settings['api_token']}";

    final dio = Dio();
    var data = await dio.get(url).then((response) {
      return response.data;
    }).catchError((err) {
      print(err);
      return null;
    });

    print(data);

    if (data != null && data['status'].toString() == 'ok') {
      _selectId = (data['id'] ?? id).toString();
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
    await _refreshInfoPath();
  }

  Future<void> _postLoop() async {
    setState(() {
      _loading = true;
    });
    var url =
        "${AppDefine.baseURL}app/info_video_loop?loop=$_loop&code=$_code&token=${AppManager.settings['api_token']}";

    final dio = Dio();
    var data = await dio.get(url).then((response) {
      return response.data;
    }).catchError((err) {
      print(err);
      return null;
    });

    print(data);

    if (data != null && data['status'].toString() == 'ok') {
      _loop = data['loop'].toString();
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  String? _asPath(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty || text == 'null') return null;
    return text;
  }

  String? _pathFromItem(dynamic item) {
    if (item is! Map) return null;
    const keys = [
      'path',
      'file',
      'url',
      'video',
      'filepath',
      'file_path',
      'filename',
      'file_name',
      'src',
      'movie',
    ];
    for (final key in keys) {
      final value = _asPath(item[key]);
      if (value != null) return value;
    }
    for (final value in item.values) {
      final text = value?.toString() ?? '';
      final lower = text.toLowerCase();
      if (lower.endsWith('.mp4') ||
          lower.endsWith('.mov') ||
          lower.endsWith('.m4v')) {
        return text;
      }
    }
    return null;
  }

  Future<void> _refreshInfoPath() async {
    final url =
        '${AppDefine.baseURL}api/info?code=$_code&mst_id=${AppManager.myId}';
    try {
      final data = await _dio().get(url).then((response) => response.data);
      if (data is Map) {
        final video = _asPath(data['video']);
        if (video != null) {
          _infoVideoPath = video;
        }
      }
    } catch (e) {
      print('refresh info path $e');
    }
  }

  Future<String?> _resolvePlayPath() async {
    if (_infoVideoPath.isNotEmpty) {
      return _infoVideoPath;
    }
    if (_selectId.isNotEmpty && _selectId != 'null') {
      for (final item in _data) {
        if (item['id'].toString() == _selectId) {
          final fromItem = _pathFromItem(item);
          if (fromItem != null) return fromItem;
          break;
        }
      }
    }
    await _refreshInfoPath();
    if (_infoVideoPath.isNotEmpty) {
      return _infoVideoPath;
    }
    for (final item in _data) {
      final fromItem = _pathFromItem(item);
      if (fromItem != null) return fromItem;
    }
    return null;
  }

  Future<void> _goHomeAndPlay() async {
    if (_playBusy) return;
    setState(() {
      _playBusy = true;
    });
    try {
      final path = await _resolvePlayPath();
      if (!mounted) return;
      if (path == null) {
        await _showDialog('再生する動画を選択してください');
        return;
      }
      AppManager.pendingPlayInfoVideo = true;
      AppManager.pendingPlayInfoVideoPath = path;
      Navigator.of(context).pop('play');
    } finally {
      if (mounted) {
        setState(() {
          _playBusy = false;
        });
      }
    }
  }

  Widget _playContainer() {
    return TvSettingFocus(
      onActivate: _goHomeAndPlay,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: Container(
          height: TvUtil.isTelevision ? 64 : WidgetUtil.listHeight,
          padding: const EdgeInsets.all(10.0),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color.fromARGB(255, 220, 220, 220)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _playBusy ? '読み込み中...' : '再生',
                style: TextStyle(fontSize: TvUtil.isTelevision ? 22 : 14),
              ),
              if (_playBusy)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              else
                Icon(
                  Icons.play_circle_fill,
                  color: Colors.blue,
                  size: TvUtil.isTelevision ? 36 : 28,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loopContainer() {
    return TvSettingFocus(
      autofocus: true,
      onActivate: () {
        _loop = _loop == '1' ? '0' : '1';
        _postLoop();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: Container(
          height: TvUtil.isTelevision ? 64 : WidgetUtil.listHeight,
          padding: const EdgeInsets.all(10.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '繰り返し再生',
                style: TextStyle(fontSize: TvUtil.isTelevision ? 22 : 14),
              ),
              ExcludeFocus(
                child: CupertinoSwitch(
                  value: _loop == '1',
                  onChanged: (value) {
                    _loop = value ? '1' : '0';
                    _postLoop();
                  },
                  activeTrackColor: Colors.blue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listContainer(int index) {
    final item = _data[index];
    final itemId = item['id'].toString();
    final selected = itemId == _selectId;

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Container(
        height: TvUtil.isTelevision ? 64 : WidgetUtil.listHeight,
        padding: const EdgeInsets.all(10.0),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color.fromARGB(255, 220, 220, 220)),
          ),
        ),
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
      onActivate: () {
        _selectVideo(itemId);
      },
      child: row,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: WidgetUtil.appBar(
        TvUtil.isTelevision ? 'ビデオ' : 'お知らせ動画',
        backgroundColor: WidgetUtil.iosNavbarBG,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView.builder(
              itemBuilder: (BuildContext context, int index) {
                if (index == 0) {
                  return _loopContainer();
                }
                if (!TvUtil.isTelevision) {
                  if (index == 1) {
                    return _playContainer();
                  }
                  return _listContainer(index - 2);
                }
                return _listContainer(index - 1);
              },
              itemCount: _data.length + (TvUtil.isTelevision ? 1 : 2),
            ),
            if (_loading) WidgetUtil.loadingIndicator,
          ],
        ),
      ),
    );
  }
}
