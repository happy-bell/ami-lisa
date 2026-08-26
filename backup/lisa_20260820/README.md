# ami-LiSA（旧 TCLアミ）関連バックアップ（2026-08-20）

ホーム画面切替・設定・時計画面を ami-EX と同じ動作にする直前の控え。
名称に LiSA を含む。フルスナップショットは `backup/tcl_ami_20260818/`。

## 入っているもの
- `lib/pages/setting/setting_page.dart` … LiSA/EX 共通設定画面
- `lib/pages/setting/setting_select_page.dart` … ホーム画面名称（TCLアミ／ラズパイ版）
- `lib/pages/setting/tv_pi_setting_page.dart` … EX 旧設定-ログイン
- `lib/pages/room/room_page.dart` … 居室／時計／設定戻り
- `lib/widgets/clock_widget.dart` … 時計画面
- `lib/services/appmanager.dart` … tvLayout ラベル

戻すときは対応パスへコピーし直す。
