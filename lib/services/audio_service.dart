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
    if (_ringtone != null) {
      return;
    }
    // _ringtone = AudioPlayer();
    // await _ringtone!.setReleaseMode(ReleaseMode.loop);
    // // final session = await AudioSession.instance;
    // // await session.configure(AudioSessionConfiguration.music());
    if (AppManager.appsettings['RINGTONE'] != '0') {
      dlRingtone();
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
      assetRingtone();
    }
  }

  Future<void> assetRingtone() async {
    _ringtone = AssetsAudioPlayer();
    await _ringtone!.open(Audio(
      '/assets/sounds/ringtone.mp3',
    ), loopMode: LoopMode.single);
    await _ringtone!.play();
  }

  Future<void> dlRingtone() async {
      var filename = 'dlringtone.mp3';
      String localpath = '${(await getApplicationDocumentsDirectory()).path}/$filename';
      print(localpath);
      var exist = await File(localpath).exists();
      if (!exist) {
        print('file none');
        return;
      }
    _ringtone = AssetsAudioPlayer();
    await _ringtone!.open(Audio.file(
      localpath,
    ), loopMode: LoopMode.single);
    await _ringtone!.play();
  }

  Future<void> stopRingtone() async {
    print('[DEBUG PRINT] stop  ringtone');
    if (_ringtone != null) {
      await _ringtone!.stop();
      _ringtone!.dispose();
      _ringtone = null;
    }
  }
}