import 'dart:io';
import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:path_provider/path_provider.dart';
import 'appmanager.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();

  AudioService._internal();

  AssetsAudioPlayer? _ringtone;
  AssetsAudioPlayer? _call;
  AssetsAudioPlayer? _buttonCall;
  
  // 着信音の状態管理
  bool _isRingtoneActive = false;

  factory AudioService() {
    return _instance;
  }

  Future<void> call() async {
    if (_call != null) {
      return;
    }
    _call = AssetsAudioPlayer();
    await _call!.open(Audio(
      '/assets/sounds/call.mp3'
    ), loopMode: LoopMode.single);
    await _call!.play();
  }

  Future<void> stopCall() async {
    if (_call == null) {
      return;
    }
    await _call?.stop();
    _call?.dispose();
    _call = null;
  }

  Future<void> buttonCall() async {
    if (_buttonCall != null) {
      return;
    }
    _buttonCall = AssetsAudioPlayer();
    await _buttonCall!.open(Audio(
      '/assets/sounds/sound1.mp3',
    ), loopMode: LoopMode.single);
    await _buttonCall!.play();
  }

  Future<void> stopButtonCall() async {
    if (_buttonCall == null) {
      return;
    }
    await _buttonCall!.stop();
    _buttonCall!.dispose();
    _buttonCall = null;
  }

  Future<void> ringtone() async {
    // 既に着信音が再生中の場合は何もしない
    if (_isRingtoneActive) {
      print('[DEBUG PRINT] ringtone already active, skipping');
      return;
    }
    // _ringtone = AudioPlayer();
    // await _ringtone!.setReleaseMode(ReleaseMode.loop);
    // // final session = await AudioSession.instance;
    // // await session.configure(AudioSessionConfiguration.music());

    print('[DEBUG PRINT] starting ringtone - RINGTONE setting: ${AppManager.appsettings['RINGTONE']}');
    _isRingtoneActive = true;

    if (AppManager.appsettings['RINGTONE'] != '0') {
      await dlRingtone();

    //   var filename = 'dlringtone.mp3';
    //   String localpath = '${(await getApplicationDocumentsDirectory()).path}/$filename';
    //   print(localpath);
    //   var exist = await File(localpath).exists();
    //   if (!exist) {
    //     print('file none');
    //     return;
    //   }
      // await _ringtone!.setAsset(localpath);
    } else {
      await assetRingtone();
    }
  }

  Future<void> assetRingtone() async {
    try {
      // 既存の着信音を停止
      await _stopRingtoneInternal();
      
      print('[DEBUG PRINT] starting asset ringtone');
      _ringtone = AssetsAudioPlayer();
      await _ringtone!.open(Audio(
        '/assets/sounds/ringtone.mp3',
      ), loopMode: LoopMode.single);
      await _ringtone!.play();
      print('[DEBUG PRINT] asset ringtone started successfully');
    } catch (e) {
      print('[DEBUG PRINT] error starting asset ringtone: $e');
      _isRingtoneActive = false;
    }
  }

  Future<void> dlRingtone() async {
    try {
      // 既存の着信音を停止
      await _stopRingtoneInternal();
      
      var filename = 'dlringtone.mp3';
      String localpath = '${(await getApplicationDocumentsDirectory()).path}/$filename';
      print('[DEBUG PRINT] checking dl ringtone path: $localpath');
      
      var exist = await File(localpath).exists();
      if (!exist) {
        print('[DEBUG PRINT] dl ringtone file not found, falling back to asset');
        await assetRingtone();
        return;
      }
      
      print('[DEBUG PRINT] starting dl ringtone');
      _ringtone = AssetsAudioPlayer();
      await _ringtone!.open(Audio.file(
        localpath,
      ), loopMode: LoopMode.single);
      await _ringtone!.play();
      print('[DEBUG PRINT] dl ringtone started successfully');
    } catch (e) {
      print('[DEBUG PRINT] error starting dl ringtone: $e, falling back to asset');
      await assetRingtone();
    }
  }

  // 内部的な停止処理（重複を避けるため）
  Future<void> _stopRingtoneInternal() async {
    if (_ringtone != null) {
      try {
        await _ringtone!.stop();
        _ringtone!.dispose();
      } catch (e) {
        print('[DEBUG PRINT] error stopping previous ringtone: $e');
      }
      _ringtone = null;
    }
  }

  Future<void> stopRingtone() async {
    print('[DEBUG PRINT] stop ringtone called - active: $_isRingtoneActive');
    
    if (!_isRingtoneActive) {
      print('[DEBUG PRINT] ringtone not active, but checking for instance');
    }
    
    _isRingtoneActive = false;
    
    if (_ringtone != null) {
      try {
        print('[DEBUG PRINT] stopping ringtone instance');
        await _ringtone!.stop();
        _ringtone!.dispose();
        print('[DEBUG PRINT] ringtone stopped and disposed successfully');
      } catch (e) {
        print('[DEBUG PRINT] error stopping ringtone: $e');
      }
      _ringtone = null;
    } else {
      print('[DEBUG PRINT] no ringtone instance to stop');
    }
  }
  
  // 着信音が再生中かどうかを確認するメソッド
  bool get isRingtoneActive => _isRingtoneActive;
}