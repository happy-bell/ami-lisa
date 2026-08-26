<?php
// ====================================================================
// tv_bind_serial.php
//
// Google TV（ami-LiSA / ami-EX）がログインしたとき、
// 管理画面で先に登録した serial_no に code と mst_id を結びつける。
// テレビ電話アミ（46amip4 index.php ログイン時）と同じ UPDATE。
//
// 手順:
//   1) Web管理で ami_serial_nos に serial_no だけ登録する
//   2) Google TV がログインし、sn / code / mst_id をこの API に送る
//   3) serial_no が一致した行の code, mst_id を更新する
//
// 配置先（health_json_by_udid.php と同じフォルダ。新規追加のみ）:
//   /frinurse/newhealthcare46amip4/tv_bind_serial.php
// URL:
//   https://mcs-a.com/frinurse/newhealthcare46amip4/tv_bind_serial.php
//
// POST または GET:
//   sn      Android ID（例: f08aa289889d2136）
//   code    委託者コード（例: fBNWB6s1）
//   mst_id  マスタID（例: TV005）  ※ fBNWB6s1_TV005 でも可
//   token   AppDefine.getDelegatorToken() と同じ値
// ====================================================================

$incDir = '../include/';
include($incDir . 'inc.php');
include($incDir . 'func.php');
include($incDir . 'mysqldb.php');

header('Content-Type: application/json; charset=utf-8');

$raw = file_get_contents('php://input');
$json = json_decode($raw, true);
if (!is_array($json)) {
  $json = array();
}

function tv_bind_param($json, $key) {
  if (isset($json[$key]) && $json[$key] !== '') {
    return trim((string)$json[$key]);
  }
  if (isset($_POST[$key]) && $_POST[$key] !== '') {
    return trim((string)$_POST[$key]);
  }
  if (isset($_GET[$key]) && $_GET[$key] !== '') {
    return trim((string)$_GET[$key]);
  }
  return '';
}

$sn = tv_bind_param($json, 'sn');
$code = tv_bind_param($json, 'code');
$mstId = tv_bind_param($json, 'mst_id');
$token = tv_bind_param($json, 'token');

$expectedToken = 'hP5ppMqMwGeQ6Gh5MUAz7ZaBQT8WedxZ';
if ($token !== $expectedToken) {
  echo json_encode(array('status' => 'error', 'message' => 'invalid token'));
  exit;
}

if ($sn === '' || $code === '' || $mstId === '') {
  echo json_encode(array('status' => 'error', 'message' => 'sn, code, mst_id required'));
  exit;
}

if (strpos($mstId, $code . '_') === 0) {
  $mstId = substr($mstId, strlen($code) + 1);
}

if (!preg_match('/^[A-Za-z0-9._:-]+$/', $sn) ||
    !preg_match('/^[A-Za-z0-9]+$/', $code) ||
    !preg_match('/^[A-Za-z0-9]+$/', $mstId)) {
  echo json_encode(array('status' => 'error', 'message' => 'invalid characters'));
  exit;
}

$amidb = new MySqlDB();
if (!$amidb->connect($amicon)) {
  echo json_encode(array('status' => 'error', 'message' => 'db connect failed'));
  exit;
}

$row = $amidb->selectOne(sprintf(
  "select * from ami_serial_nos where serial_no = '%s'",
  $sn
));

if ($row == null) {
  echo json_encode(array(
    'status' => 'error',
    'message' => 'serial_no not registered',
    'serial_no' => $sn,
  ));
  exit;
}

$curCode = isset($row['code']) ? trim((string)$row['code']) : '';
$curMst = isset($row['mst_id']) ? trim((string)$row['mst_id']) : '';
if ($curCode === $code && $curMst === $mstId) {
  echo json_encode(array(
    'status' => 'ok',
    'action' => 'already',
    'serial_no' => $sn,
    'code' => $code,
    'mst_id' => $mstId,
  ));
  exit;
}

$ok = $amidb->exec(sprintf(
  "update ami_serial_nos set code = '%s', mst_id = '%s', updated_at = NOW() where serial_no = '%s'",
  $code, $mstId, $sn
));
if (!$ok) {
  $ok = $amidb->exec(sprintf(
    "update ami_serial_nos set code = '%s', mst_id = '%s' where serial_no = '%s'",
    $code, $mstId, $sn
  ));
}

echo json_encode(array(
  'status' => $ok ? 'ok' : 'error',
  'action' => $ok ? 'update' : 'update_failed',
  'serial_no' => $sn,
  'code' => $code,
  'mst_id' => $mstId,
));
