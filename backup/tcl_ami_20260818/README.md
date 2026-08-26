# TCLアミ一時保留スナップショット（2026-08-18）

TCLアミ開発をここで止めた時点のソース一式。ラズパイ版ホームの作業ではこの内容を上書きしない。
戻すときは、対応パスへコピーし直す。

## 入っているもの
- `lib/` … Dart 全体（居室・設定・A&D・Ring/Checkme・通話）
- `android/kotlin/` … USBカメラ機種別プロファイル、UAC、着信オーバーレイ
- `android/cpp/` … `usb_audio_jni.cpp` / CMakeLists
- `android/AndroidManifest.xml` / `android/res/xml/usb_device_filter.xml`
- `camera_profiles/` … 凍結した機種別プロファイルの控え
- `docs/TCLアミ_構築の流れ_20260818.docx`

## この時点で確定しているカメラ
| 名前 | id | VID/PID | 状態 |
|------|----|---------|------|
| C270n | c270n | 0x046D | 凍結・良好 |
| USB2.0-A Buffalo BSW505MBK | usb20a | 0x0411 / 730 | 凍結・良好（接続中はこちら） |
| USB2.0-B | usb20b | 0x0411 / 730 | 凍結・ファイル保持 |
| TZZ | tzz | 0x0C45 / 0x636B | 有効 |
| EMEET C960 | emeet | 0x328F | 波うち未解消で保留 |

## ラズパイ版へ移るときの約束
- 変更は `AppManager.isPiTvLayout == true` のときだけ効かせる
- TCLアミ（`!isPiTvLayout`）とスタッフ（`MCSTYPE == '5'`）は触らない
- 上記カメラプロファイルの数値は書き換えない
- ホーム切替は設定の「ホーム画面」→ ラズパイ版。デフォルトは TCLアミのまま

機種別の細かい控えは `backup/usb20a_profile_20260818/` など既存フォルダも残してある。
