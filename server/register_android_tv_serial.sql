-- ami_serial_nos へ Android TV を追加する（既存行は変更しない）
-- phpMyAdmin の SQL タブで実行してください。
--
-- 追加する組み合わせ:
--   serial_no = 3af46636ffa8e018
--   code      = fBNWB6s1
--   mst_id    = TV007
--
-- ラズパイ行 10000000270975f2 は削除・上書きしない。

INSERT INTO ami_serial_nos (serial_no, code, mst_id, created_at, updated_at)
SELECT '3af46636ffa8e018', 'fBNWB6s1', 'TV007', NOW(), NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM ami_serial_nos WHERE serial_no = '3af46636ffa8e018'
);

-- 上でエラーになる場合（フラグ列が必須など）は、同じテーブルの他行を
-- phpMyAdmin の「コピー」で複製し、serial_no だけ 3af46636ffa8e018 に変える。
-- code = fBNWB6s1、mst_id = TV007、フラグは他行と同じ 0 にする。
