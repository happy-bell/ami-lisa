# USB2.0-B プロファイル保存（2026-08-17 実機良好）

権限ダイアログの名称: USB 2.0 Camera（TZZ と同じ表示なので VID/PID で区別）

- アプリ内名前: USB2.0-B / id=`usb20b`
- VID: 0x0411 (1041) / PID: 730
- メーカー: Sonix Technology Co., Ltd.
- ソース: `android/app/src/main/kotlin/com/frinurse/amiapp/CameraUsb20BProfile.kt`

## 実機で採用した値
- 映像: 640x360 @ 15fps（綺麗）
- 音声: UAC 強制（HAL の USB 入力は無音になる）
- inputGain: 11
- UAC バッファ: 目標 80ms / 上限 140ms（映像より音が約0.5秒遅れていた対策）
- エコー: duckGain 0.20（スマホからの回り込みを若干軽減）

## 他カメラ
C270n / EMEET / TZZ の値は別ファイル。このプロファイルをコピーして上書きしない。
