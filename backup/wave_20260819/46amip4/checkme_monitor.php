<?php
// ====================================================================
// checkme_monitor.php — Checkme Advance ライブモニタ
//
// レイアウトは実機で確認済みの版に準拠：
//   ヘッダー（誘導番号1 / 受信状態 / Mark）
//   波形エリア：上段ECG（緑）／下段SpO2脈波（水色）
//   右パネル：HR/min・%SpO2・PR・PI の4段（水色の区切り線）
//
// 単体表示でも iframe（幅50%など）でも崩れないよう、
//   ・ヘッダーは固定高さ（潰れて数値と重ならない）
//   ・文字サイズはコンテナ幅に追随（cqw）
//   ・格子は幅に応じてマス数を一定に保つ
//
// データと制御: ラズパイのローカルApache
//   http://localhost/ami_ecg_live.json    （波形）
//   http://localhost/checkme_register.php （開始/停止）
//
// 配置先: newhealthcare46amip3/ 直下
//
// 親ページ（index.php）への通知:
//   {type:'checkme-close'}                  自動クローズ要求
//   {type:'checkme-data', hr, spo2, pr, pi} 通話相手への共有用
// ====================================================================
?>
<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Check Monitor</title>
<style>
  * { box-sizing:border-box; margin:0; padding:0; }
  html, body { height:100%; background:transparent; }
  body { color:#e8f0f8; overflow:hidden; opacity:0.7;
         font-family:"Hiragino Sans","Yu Gothic",sans-serif; padding:4px; }

  /* container-type により、内部の cqw が「この枠の幅」基準になる */
  .frame { height:100%; display:flex; flex-direction:column;
           background:#000; border-radius:6px; overflow:hidden;
           container-type:inline-size; }

  /* ヘッダー：固定高さ。ここが潰れると右パネルと重なるため px 指定。 */
  .head { height:34px; flex:0 0 34px; display:flex; align-items:center;
          padding:0 10px; gap:10px; background:#1a1a1a; }
  .head .lead  { font-size:15px; color:#22e022; font-weight:600; }
  .head .right { margin-left:auto; display:flex; align-items:center; gap:10px; }
  .head .state { font-size:12px; color:#9aa6ad; white-space:nowrap; }
  .head .mark  { background:#1e9dfa; color:#fff; border:none; border-radius:4px;
                 padding:5px 14px; font-size:13px; cursor:pointer; }

  .body   { flex:1 1 auto; display:flex; min-height:0; }
  .screen { flex:1 1 auto; min-width:0; position:relative; }
  .screen canvas { width:100%; height:100%; display:block; }

  /* 右パネル：4セルで縦いっぱいを均等分割 */
  .side { width:22cqw; min-width:120px; max-width:190px; flex:0 0 auto;
          display:flex; flex-direction:column; border-left:2px solid #1e9dfa; }
  .cell { flex:1 1 0; min-height:0; display:flex; flex-direction:column;
          align-items:center; justify-content:center;
          border-bottom:2px solid #1e9dfa; padding:2px; }
  .cell:last-child { border-bottom:none; }

  .cell .k { font-size:2.4cqw; white-space:nowrap; }
  .cell .v { font-weight:700; line-height:1.05; font-variant-numeric:tabular-nums; }
  .cell .u { font-size:2cqw; }
  .hr .k, .spo2 .k { font-size:2.8cqw; }

  .hr   .k, .hr   .v { color:#22e022; }
  .spo2 .k, .spo2 .v { color:#1e9dfa; }
  .pr   .k, .pr .v, .pr .u { color:#1e9dfa; }
  .pi   .k, .pi   .v { color:#1e9dfa; }

  .hr   .v { font-size:10cqw; }
  .spo2 .v { font-size:9.5cqw; }
  .pr   .v { font-size:6.5cqw; }
  .pi   .v { font-size:6.5cqw; }

  .idle .v { opacity:.45; }
</style>
</head>
<body>

<div class="frame">
  <div class="head">
    <!--<span class="lead">1</span>-->
    <span class="right">
      <span class="state" id="state">受信 --</span>
      <!--<button class="mark" id="btnMark">Mark</button>-->
    </span>
  </div>

  <div class="body">
    <div class="screen"><canvas id="cv"></canvas></div>
    <div class="side">
      <div class="cell hr">
        <div class="k">HR/min</div><div class="v" id="vHr">--</div>
      </div>
      <div class="cell spo2">
        <div class="k">%SpO2</div><div class="v" id="vSpo2">--</div>
      </div>
      <div class="cell pr">
        <div class="k">PR</div><div class="v" id="vPr">--</div><div class="u">/min</div>
      </div>
      <div class="cell pi">
        <div class="k">PI</div><div class="v" id="vPi">--</div>
      </div>
    </div>
  </div>
</div>

<script>
const LIVE_URL = "http://localhost/ami_ecg_live.json";
const CTL_URL  = "http://localhost/checkme_register.php";
const POLL_MS  = 200;
const NO_DATA_CLOSE_MS = 60000;          // 60秒データなしで自動クローズ

// ===== 受信専用モード（通話相手側） =====
// ?mode=remote で開くと、ローカル(localhost)には一切アクセスせず、
// 親ページから postMessage で送られてくる波形・数値だけを描画する。
// 測定側（患者側）から通話経路で同期されたデータを表示するために使う。
const REMOTE = location.search.indexOf("mode=remote") >= 0;
const SHARE_INTERVAL_MS = 400;           // 相手へ波形を送る間隔
const SHARE_DECIMATE = 2;                // 送信時の間引き（2 = 62.5Hz相当）
let lastShareAt = 0;

const BG         = "#000";
const GRID_FINE  = "#262e29";            // 細線
const GRID_MED   = "#3c473f";            // 中線（5マスごと）
const GRID_MAJOR = "#78867c";            // 太線（25マスごと）
const COL_ECG    = "#22e022";
const COL_PLE    = "#37b6f0";
// 横に並ぶ最小マスの数。大きいほどマスが細かい＝太線の枠も小さくなる。
// 180 は「枠の大きさを 1/2」に相当（従来 90）。
const CELLS_ACROSS = 180;

const cv = document.getElementById("cv");
const cx = cv.getContext("2d");
let ecg = [], pleth = [], measuring = false;
let lastDataAt = Date.now();
let closed = false;
let mmPx = 8, markX = null;

function fit() {
  const r = cv.getBoundingClientRect();
  cv.width  = Math.max(2, Math.floor(r.width  * devicePixelRatio));
  cv.height = Math.max(2, Math.floor(r.height * devicePixelRatio));
  mmPx = Math.max(3, r.width / CELLS_ACROSS);
}
window.addEventListener("resize", fit);
setTimeout(fit, 0);

function gridStyle(i, dpr) {
  if (i % 25 === 0) return [GRID_MAJOR, 1.4 * dpr];
  if (i % 5  === 0) return [GRID_MED,   0.9 * dpr];
  return [GRID_FINE, 0.4 * dpr];
}

function drawGrid(w, h) {
  cx.fillStyle = BG;
  cx.fillRect(0, 0, w, h);
  const dpr = devicePixelRatio, mm = mmPx * dpr;
  // 細→中→太の順に重ね、太線を最前面にする
  for (const pass of [0, 1, 2]) {
    for (let i = 0; i * mm <= w; i++) {
      const M = (i % 25 === 0), D = (i % 5 === 0);
      if (pass === 0 && (D || M)) continue;
      if (pass === 1 && (!D || M)) continue;
      if (pass === 2 && !M) continue;
      const st = gridStyle(i, dpr);
      cx.strokeStyle = st[0]; cx.lineWidth = st[1];
      const x = Math.round(i * mm) + 0.5;
      cx.beginPath(); cx.moveTo(x, 0); cx.lineTo(x, h); cx.stroke();
    }
    for (let j = 0; j * mm <= h; j++) {
      const M = (j % 25 === 0), D = (j % 5 === 0);
      if (pass === 0 && (D || M)) continue;
      if (pass === 1 && (!D || M)) continue;
      if (pass === 2 && !M) continue;
      const st = gridStyle(j, dpr);
      cx.strokeStyle = st[0]; cx.lineWidth = st[1];
      const y = Math.round(j * mm) + 0.5;
      cx.beginPath(); cx.moveTo(0, y); cx.lineTo(w, y); cx.stroke();
    }
  }
}

function plot(data, top, bottom, color) {
  if (!data || data.length < 4) return;
  const w = cv.width;
  let lo = Infinity, hi = -Infinity;
  for (let i = 0; i < data.length; i++) {
    const v = data[i];
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  const span = Math.max(1, hi - lo);
  const band = bottom - top, pad = band * 0.12;
  const step = w / (data.length - 1);
  cx.strokeStyle = color;
  cx.lineWidth = Math.max(1.2, 2.0 * devicePixelRatio * (w / 1400));
  cx.lineJoin = "round"; cx.lineCap = "round";
  cx.beginPath();
  for (let i = 0; i < data.length; i++) {
    const x = i * step;
    const y = bottom - pad - ((data[i] - lo) / span) * (band - pad * 2);
    if (i === 0) cx.moveTo(x, y); else cx.lineTo(x, y);
  }
  cx.stroke();
}

// 右パネル「%SpO2」セルの下端に、波形の上下分割を合わせる
function splitY() {
  const cell = document.querySelector(".cell.spo2");
  if (!cell) return cv.height * 0.5;
  const cr = cv.getBoundingClientRect(), br = cell.getBoundingClientRect();
  const y = (br.bottom - cr.top) * devicePixelRatio;
  return Math.max(cv.height * 0.2, Math.min(cv.height * 0.8, y));
}

function render() {
  const w = cv.width, h = cv.height;
  drawGrid(w, h);
  const sy = splitY();
  plot(ecg,   0,  sy, COL_ECG);
  plot(pleth, sy, h,  COL_PLE);
  if (markX !== null) {
    cx.strokeStyle = "#ffd23f";
    cx.lineWidth = 2 * devicePixelRatio;
    cx.beginPath(); cx.moveTo(markX, 0); cx.lineTo(markX, h); cx.stroke();
  }
  requestAnimationFrame(render);
}
requestAnimationFrame(render);

document.getElementById("btnMark") && document.getElementById("btnMark").addEventListener("click", function () {
  markX = cv.width - 4;
  setTimeout(function () { markX = null; }, 4000);
});

function setNum(id, val, digits) {
  const el = document.getElementById(id);
  if (val === null || val === undefined || val === 0) { el.textContent = "--"; return; }
  el.textContent = (digits === undefined) ? val : Number(val).toFixed(digits);
}

function ctl(action) {
  return fetch(CTL_URL + "?action=" + action, { cache: "no-store" })
           .then(function (r) { return r.json(); })
           .catch(function () { return null; });
}

function closeMonitor() {
  if (closed) return;
  closed = true;
  if (!REMOTE) ctl("stop");        // 受信側は測定していないので停止要求しない
  try { parent.postMessage({ type: "checkme-close" }, "*"); } catch (e) {}
}

async function poll() {
  if (closed) return;
  try {
    const r = await fetch(LIVE_URL + "?t=" + Date.now(), { cache: "no-store" });
    const d = await r.json();
    measuring = !!d.measuring;
    ecg   = d.ecg   || [];
    pleth = d.pleth || [];
    setNum("vHr", d.hr); setNum("vSpo2", d.spo2);
    setNum("vPr", d.pr); setNum("vPi", d.pi, 1);
    document.body.classList.toggle("idle", !measuring);

    if (measuring && (d.hr || d.spo2)) {
      lastDataAt = Date.now();
      // 通話相手へ共有：数値は毎回、波形は間隔をあけて間引いて送る
      const now = Date.now();
      const sendWave = (now - lastShareAt) >= SHARE_INTERVAL_MS;
      if (sendWave) lastShareAt = now;
      try {
        parent.postMessage({
          type: "checkme-data",
          hr: d.hr, spo2: d.spo2, pr: d.pr, pi: d.pi, session: d.session,
          ecg:   sendWave ? ecg.filter(function (_, i) { return i % SHARE_DECIMATE === 0; }) : null,
          pleth: sendWave ? pleth.filter(function (_, i) { return i % SHARE_DECIMATE === 0; }) : null
        }, "*");
      } catch (e) {}
    }

    if (measuring) {
      document.getElementById("state").textContent = "受信中";
    } else {
      const left = Math.max(0, NO_DATA_CLOSE_MS - (Date.now() - lastDataAt));
      document.getElementById("state").textContent = "受信 -- (" + Math.ceil(left / 1000) + ")";
    }

    if (Date.now() - lastDataAt > NO_DATA_CLOSE_MS) closeMonitor();
  } catch (e) {
    document.getElementById("state").textContent = "受信エラー";
    document.body.classList.add("idle");
  }
}

function asNumArray(v) {
  if (typeof v === "string") {
    try { v = JSON.parse(v); } catch (e) { return null; }
  }
  if (Array.isArray(v)) return v;
  if (v && typeof v === "object") {
    const out = [];
    for (let i = 0; i < 20000; i++) {
      if (v[i] === undefined) break;
      const n = Number(v[i]);
      if (!isNaN(n)) out.push(n);
    }
    return out.length ? out : null;
  }
  return null;
}

if (REMOTE) {
  // ===== 受信専用モード（通話相手側） =====
  // localhost には触れず、親から届くデータだけを描画する。
  document.getElementById("state").textContent = "相手の測定データ";
  document.body.classList.add("idle");
  window.addEventListener("message", function (ev) {
    const d = ev.data || {};
    if (d.type !== "checkme-remote-data") return;
    const ecgIn = asNumArray(d.ecg);
    const pleIn = asNumArray(d.pleth);
    if (ecgIn && ecgIn.length) ecg = ecgIn;
    if (pleIn && pleIn.length) pleth = pleIn;
    setNum("vHr", d.hr); setNum("vSpo2", d.spo2);
    setNum("vPr", d.pr); setNum("vPi", d.pi, 1);
    lastDataAt = Date.now();
    document.body.classList.remove("idle");
    document.getElementById("state").textContent = "相手の測定データ";
  });
  // 一定時間データが来なければ薄く表示する（通話中の目印は残す）
  setInterval(function () {
    if (Date.now() - lastDataAt > 8000) {
      document.body.classList.add("idle");
      document.getElementById("state").textContent = "相手の測定 待機中";
    }
  }, 2000);
} else {
  // ===== 通常モード（測定側） =====
  ctl("start").then(function (res) {
    lastDataAt = Date.now();
    if (res && res.daemon === false) {
      document.getElementById("state").textContent = "受信サービス未起動";
    }
    poll();
    setInterval(poll, POLL_MS);
  });
}

// ※ pagehide では測定を止めない。
//    通話終了時にページがリロードされると iframe も破棄されるため、
//    ここで停止すると復元後に測定が切れてしまう。
//    停止は「閉じる操作（親ページ）」と「60秒無データの自動クローズ」で行う。
</script>
</body>
</html>
