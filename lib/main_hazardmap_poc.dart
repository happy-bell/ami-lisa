// 動作確認専用の一時エントリポイント。HazardMapPage単体を直接起動する。
// 本番ビルド(main.dart)には影響しない。確認後は削除して構わない。
import 'package:amiapp/pages/room/hazard_map_page.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: HazardMapPage(),
  ));
}
