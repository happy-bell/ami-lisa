<?php
// ====================================================================
// tv_register_serial.php  （新規ファイル。既存 Web は変更しない）
//
// ami_serial_nos に Android TV シリアルを追加する。
// ラズパイのシリアルは触らない。
//
// 配置先（fun-talk の ami DB を見ている PHP と同じ階層）:
//   管理画面で ami_serial_nos を見ているサーバー側に置く。
//   または phpMyAdmin で server/register_android_tv_serial.sql を実行する。
//
// この部屋の登録内容:
//   serial_no = 3af46636ffa8e018
//   code      = fBNWB6s1
//   mst_id    = TV007
// ====================================================================

$incDir = '../include/';
if (!is_file($incDir . 'mysqldb.php')) {
  echo json_encode(array('status' => 'error', 'message' => 'include not found. phpMyAdmin の SQL を実行してください'));
  exit;
}

include($incDir . 'inc.php');
include($incDir . 'func.php');
include($incDir . 'mysqldb.php');

header('Content-Type: application/json; charset=utf-8');

$sn = '3af46636ffa8e018';
$code = 'fBNWB6s1';
$mstId = 'TV007';

$amidb = new MySqlDB();
if (!$amidb->connect($amicon)) {
  echo json_encode(array('status' => 'error', 'message' => 'db connect failed'));
  exit;
}

$row = $amidb->selectOne(sprintf(
  "select * from ami_serial_nos where serial_no = '%s'",
  $sn
));

if ($row != null) {
  if ($row['code'] !== $code || $row['mst_id'] !== $mstId) {
    $amidb->exec(sprintf(
      "update ami_serial_nos set code = '%s', mst_id = '%s' where serial_no = '%s'",
      $code, $mstId, $sn
    ));
    echo json_encode(array('status' => 'ok', 'action' => 'update', 'serial_no' => $sn, 'code' => $code, 'mst_id' => $mstId));
    exit;
  }
  echo json_encode(array('status' => 'ok', 'action' => 'already', 'serial_no' => $sn, 'code' => $code, 'mst_id' => $mstId));
  exit;
}

$ok = $amidb->exec(sprintf(
  "insert into ami_serial_nos (serial_no, code, mst_id, created_at, updated_at) values ('%s', '%s', '%s', NOW(), NOW())",
  $sn, $code, $mstId
));
if (!$ok) {
  $ok = $amidb->exec(sprintf(
    "insert into ami_serial_nos (serial_no, code, mst_id) values ('%s', '%s', '%s')",
    $sn, $code, $mstId
  ));
}

echo json_encode(array(
  'status' => $ok ? 'ok' : 'error',
  'action' => $ok ? 'insert' : 'insert_failed',
  'serial_no' => $sn,
  'code' => $code,
  'mst_id' => $mstId,
));
