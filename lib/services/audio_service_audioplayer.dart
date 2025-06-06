// import 'dart:io';
// // import 'package:just_audio/just_audio.dart';
// import 'package:audioplayers/audioplayers.dart';
// import 'package:assets_audio_player/assets_audio_player.dart';
// import 'package:path_provider/path_provider.dart';
// import 'appmanager.dart';
//
// class AudioService {
//   static final AudioService _instance = AudioService._internal();
//
//   AudioService._internal();
//
//   AssetsAudioPlayer? _assetsAudioPlayer;
//   AudioPlayer? _ringtone;
//   AudioPlayer? _call;
//   AudioPlayer? _buttonCall;
//
//   factory AudioService() {
//     return _instance;
//   }
//
//   Future<void> callx() async {
//     if (_call != null) {
//       return;
//     }
//     print('call');
//     _call = AudioPlayer();
//     await _call!.setReleaseMode(ReleaseMode.loop);
//     await _call!.play(AssetSource('sounds/call.mp3'));
//   }
//
//   Future<void> call() async {
//     if (_assetsAudioPlayer != null) {
//       return;
//     }
//     print('call');
//     _assetsAudioPlayer = AssetsAudioPlayer();
//     _assetsAudioPlayer!.open(Audio(
//       '/assets/sounds/call.mp3',
//     ), loopMode: LoopMode.single);
//     // await _assetsAudioPlayer!.setLoopMode(LoopMode.playlist);
//     await _assetsAudioPlayer!.play();
//   }
//
//   Future<void> stopCallx() async {
//     if (_call == null) {
//       return;
//     }
//     await _call!.stop();
//     _call!.dispose();
//     _call = null;
//   }
//
//   Future<void> stopCall() async {
//     if (_assetsAudioPlayer == null) {
//       return;
//     }
//     await _assetsAudioPlayer!.stop();
//     _assetsAudioPlayer!.dispose();
//     _assetsAudioPlayer = null;
//   }
//
//   Future<void> buttonCall() async {
//     if (_buttonCall != null) {
//       return;
//     }
//     _buttonCall = AudioPlayer();
//     await _buttonCall!.setReleaseMode(ReleaseMode.loop);
//     await _buttonCall!.play(AssetSource('sounds/sound1.mp3'));
//   }
//
//   Future<void> stopButtonCall() async {
//     if (_buttonCall == null) {
//       return;
//     }
//     await _buttonCall!.stop();
//     _buttonCall!.dispose();
//     _buttonCall = null;
//   }
//
//   Future<void> ringtone() async {
//     if (_ringtone != null) {
//       return;
//     }
//     _ringtone = AudioPlayer();
//     await _ringtone!.setReleaseMode(ReleaseMode.loop);
//     // final session = await AudioSession.instance;
//     // await session.configure(AudioSessionConfiguration.music());
//     if (AppManager.appsettings['RINGTONE'] != '0') {
//       var filename = 'dlringtone.mp3';
//       String localpath = '${(await getApplicationDocumentsDirectory()).path}/$filename';
//       print(localpath);
//       var exist = await File(localpath).exists();
//       if (!exist) {
//         print('file none');
//         return;
//       }
//       // await _ringtone!.setAsset(localpath);
//     } else {
//       await _ringtone!.play(AssetSource('sounds/call.mp3'));
//       // await _ringtone!.setAsset('assets/sounds/call.mp3');
//       // await _ringtone!.setUrl('asset://assets/sounds/ringtone.mp3');
//     }
//     // await _ringtone!.setLoopMode(LoopMode.all);
//     // await _ringtone!.play();
//   }
//
//   Future<void> stopRingtone() async {
//     print('[DEBUG PRINT] stop  ringtone');
//     if (_ringtone != null) {
//       await _ringtone!.stop();
//       _ringtone!.dispose();
//       _ringtone = null;
//     }
//   }
// }
