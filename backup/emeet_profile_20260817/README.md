# EMEET C960 プロファイル凍結 (2026-08-17)

波うち未解消のため、ここまでの EMEET 専用調整を凍結する。
C270n / TCL付属 / TZZ の値は別ファイル。このバックアップを他カメラへコピーしない。

## 機種
- 表示名: HD Webcam eMeet C960
- VID: 0x328F (12943) / PID: 0x2013 (8211)
- ネイティブ: 1080p30、UVC、USB 2.0 複合機（映像+音声）

## 凍結した動き（EMEET のときだけ）
- 映像: 1920x1080@30 優先（640x360 PRIVATE は TCL HAL が ENOSYS）
- 音声: UAC 直接注入はしない（同じUSBを奪うと映像が悪化したため）
- 通話開始時に UVC Power Line Frequency を 60Hz へ（照明フリッカー対策）
- VP8 送信: max 3.5Mbps / 30fps / 解像度維持
- マイクゲート: C270n よりやや開け気味、inputGain 0.85

## 未解消
- スマホ側の波うち（横帯）は残った。60Hz 指定・Camera1/2・解像度変更では消えなかった。

## 他カメラへの影響
- C270n は `CameraC270nProfile` のまま。UAC 注入も従来どおり。
- TZZ は `CameraTzzProfile`。EMEET の映像ラダー / 60Hz / UAC スキップは使わない。
