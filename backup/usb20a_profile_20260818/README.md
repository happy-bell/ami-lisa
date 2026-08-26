# USB2.0-A プロファイル保存（2026-08-18 実機良好）

権限ダイアログの名称: USB 2.0 Camera（USB2.0-B / TZZ と同じ表示）

- アプリ内名前: USB2.0-A / id=`usb20a`
- 機種: Buffalo BSW505MBK
- VID: 0x0411 (1041) / PID: 730
- メーカー表示: Sonix Technology Co., Ltd.
- ソース: `android/app/src/main/kotlin/com/frinurse/amiapp/CameraUsb20AProfile.kt`

USB 上の VID/PID は USB2.0-B と同じ。接続中はこのプロファイルを優先する。
USB2.0-B のファイルと数値は変更していない。

## 実機で採用した値
- 映像: 640x360 @ 15fps（問題なし）
- 音声: UAC 強制
- 遅延: なし
- inputGain: 8
- UAC バッファ: 目標 70ms / 上限 130ms / warmup 0
- エコー: duckGain 0.55（duckAttack 0.005 / duckRelease 0.0012）
- ゲート: open 200 / close 80 / floor 0.55

出だしの減衰は、バッファ 40ms・gain 11・duck 0.20 では沈んだため、上記に調整して完了。

## 他カメラ
C270n / EMEET / TZZ / USB2.0-B の値は別ファイル。このプロファイルをコピーして上書きしない。
