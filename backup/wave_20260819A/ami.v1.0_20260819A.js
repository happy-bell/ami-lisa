var socket;
var socket2;
var callState = CALL_STATE.Stand;
let $open01 = $('#open01');
let $close01 = $('#close01');
let $open02 = $('#open02');
let $close02 = $('#close02');
let $remoteBg = $('#remotebg');
let $holdImg = $('#hold-img');
let $talkDiv = $('#talk-div');
let $multiDiv = $('#multi-div');
const tel01 = document.querySelector("#tel01");
var offcall = false;
var safetyCheckIds = '';
var remotePlayTimers = [];

// ラズパイ同士の1対1: 解像度を抑えてエンコード＋デコード同時のGPU負荷を下げる
function piCallConstraints() {
  return {
    audio: true,
    video: {
      width: { ideal: 640, max: 640 },
      height: { ideal: 480, max: 480 },
      frameRate: { ideal: 15, max: 15 }
    }
  };
}

function clearRemotePlayTimers() {
  for (var i = 0; i < remotePlayTimers.length; i++) {
    clearTimeout(remotePlayTimers[i]);
  }
  remotePlayTimers = [];
}

function scheduleRemotePlayRetries() {
  clearRemotePlayTimers();
  var delays = [200, 800, 2000];
  for (var i = 0; i < delays.length; i++) {
    remotePlayTimers.push(setTimeout(ensureRemoteVideoPlaying, delays[i]));
  }
}

function ensureRemoteVideoPlaying() {
  var v = document.getElementById('their-video');
  if (!v || !v.srcObject) {
    return;
  }
  try {
    $talkDiv.show();
  } catch (e) {}
  try {
    v.playsInline = true;
    // srcObject を付け直すとラズパイ Chromium の GPU プロセスが落ちて
    // キオスクが突然終了することがある。再生だけ再試行する。
    var p = v.play();
    if (p && typeof p.catch === 'function') {
      p.catch(function () {});
    }
  } catch (e) {}
}

// ネット復旧を確認してからリロードするヘルパ(20260723追加)
// オフライン中に location.reload するとChromiumのエラーページに落ちて
// JSが全停止し、復帰がブラウザの再試行任せ(非常に遅い)になるのを防ぐ。
// ネット接続中は従来の location.reload(true) と実質同じ動作(遅延はミリ秒程度)。
var __amiReloading = false;
function safeReload() {
  if (__amiReloading) { return; } // 多重実行ガード
  __amiReloading = true;
  var attempt = function() {
    // 実際にWebサーバーへ届くかを確認してからリロードする
    // (navigator.onLine=true でもDNS/経路が未復旧のことがあるため)
    fetch('./js/const.js?_=' + Date.now(), { cache: 'no-store' })
      .then(function() { location.reload(true); })
      .catch(function() { setTimeout(attempt, 3000); }); // 3秒ごとに再試行
  };
  try {
    if (navigator.onLine) {
      attempt();
    } else {
      var done = false;
      var go = function() {
        if (done) { return; }
        done = true;
        setTimeout(attempt, 2000); // 復帰直後は2秒待って回線安定後に確認
      };
      window.addEventListener('online', go, { once: true });
      // 保険: onlineイベントが発火しない環境向けに5秒ごとに確認
      var t = setInterval(function() {
        if (navigator.onLine) { clearInterval(t); go(); }
      }, 5000);
    }
  } catch (e) {
    location.reload(true);
  }
}

function init() {

  if (!hasGetUserMedia()) {
    setTimeout(function() {safeReload();}, 500); // 20260723変更: ネット復旧を確認してからリロード
  }

  if (!hasCamera()) {

  }

  $mainSection = $('#main-sec');
  $remoteVideo1 = $('#their-video');

  localVideo = document.getElementById('my-video');
  remoteVideo1 = document.getElementById('their-video');

  canvas = document.getElementById('canvas');
  photo = document.getElementById('photo');
  ct = canvas.getContext('2d');

  if (app.userID.length > 0) {
    setTimeout(sockConnect, 500);
  }

  $('#quit').click(function() {
    window.postMessage("quit", "*");
  });
  $('#home-btn').eq(0).focus();
}

function setCallState(nextState) {
  callState = nextState;
}
//テレビ電話ボタン　リスト
function onListBtn() {
  $talkDiv.hide();
  $open01.show();
  $('#weather').hide();/*20230402 一斉呼出の時に天気を非表示にする*/
  refreshAddressListOnline();/*開いた時点の最新状態で絞り込む*/
  if (socket) {
    socket.emit('clients_status', {});/*最新状態を即時取得*/
  }
  /* オンラインの相手だけを対象にフォーカスする */
  let $addressList = $('.address_list').filter(':visible');
  if ($addressList.size() > 0) {
    $addressList.get(0).focus();
  } else {
    $close01.focus();
  }
}
//テレビ電話ボタン　リスト
function onCallBtn() {
  $talkDiv.hide();
  app.callId = '@' + app.delegator + '_STAFF';
  doCall();
  $('#weather').hide();/*20230402 一斉呼出の時に天気を非表示にする*/    
}

function onEndBtn() {
  socket.emit('hangup', []);
  stop(false);
}

function onMultiEndBtn() {
  console.log('check multi end ' + app.talkId1 + ', ' + app.talkId2);
  let sendData = {
    "id2": "threewayToCall",
    "from": app.talkId1,
    "to": app.talkId2
  };
  socket.emit("talk", sendData);

  socket.emit('hangup', []);
  stop(false);
}

function onQuitBtn() {
  window.postMessage("quit", "*");
}
//テレビ電話リスト閉じる
function onClose01() {
  $open01.hide();
  $talkDiv.show();	
  if (app.weatherRegistered) {
    $('#weather').show();
  }  
  $('#home-btn').focus();
}
//一斉呼び出し終了
function onClose02() {
  $open02.hide();
  $talkDiv.show();	
  cancelCall();
  $('#home-btn').focus();
}

function onAddressList(udid) {
  app.callId = udid;
  $open01.hide();
  doCall();
}

function test() {
  app.threewayId = 'room1';
  app.talkId1 = 'aaa';
  $talkDiv.hide();
  $holdImg.hide();
  $multiDiv.show();
  srConnect();
  console.log(app);
}

/************************************************************************************************************************************
 Call & Talk
 */
function doCall() {
  setTimeout(callTimeout, 30 * 1000);
  tel01.play();
  $open02.show();
  $close02.focus();
  setCallState(CALL_STATE.Call);
  socket.emit('call', app.callId);
  console.log('do call', app.callId);
}

function callLocalApi() {
  var url = 'http://localhost/oncall.php';
  var request = new XMLHttpRequest();
  request.open('GET', url);
  request.onreadystatechange = function () {
    if (request.readyState != 4) {
      // リクエスト中
    } else if (request.status != 200) {
      // 失敗
    } else {
      // 取得成功
    }
  };
  request.send(null);
  setTimeout(remoteCecApi, 10 * 1000);
}

function remoteCecApi() {
  var url = 'http://localhost/remotecec.php';
  var request = new XMLHttpRequest();
  request.open('GET', url);
  request.onreadystatechange = function () {
    if (request.readyState != 4) {
      // リクエスト中
    } else if (request.status != 200) {
      // 失敗
    } else {
      // 取得成功
    }
  };
  request.send(null);
}

function checkPowerApi() {
  $.ajax({
    url: 'http://localhost/power.php',
    type: "GET",
    timeout: 300000
  })
    .done(function (data) {
      console.log(data);
    });
}

function callTimeout() {
  if (callState !== CALL_STATE.Call) {
    return;
  }
  cancelCall();
}
/*呼出中止*/
function cancelCall() {
  tel01.pause();
  setCallState(CALL_STATE.Stand);
  socket.emit('call_cancel', app.callId);
  app.callId = '';
  stop(false);
}

function called() {

  let options = {
    localVideo : localVideo,
    remoteVideo : remoteVideo1,
    onicecandidate : onSockIceCandidate,
    mediaConstraints: piCallConstraints()
  };

  let webRtcPeer = kurentoUtils.WebRtcPeer.WebRtcPeerSendrecv(options, function(error) {
    if (error) {
      onErrorCalled(error);
      return;
    }

    this.connectionId = app.talkId1;
    peers[app.talkId1] = webRtcPeer;

    this.generateOffer(function(error, offerSdp) {
      if (error) {
        onErrorCalled(error);
        return;
      }

      if (candidatesQueue[this.connectionId]) {
        console.log('drain candidate');
        while(candidatesQueue[this.connectionId].length) {
          let candidate = candidatesQueue[this.connectionId].shift();
          this.addIceCandidate(candidate);
        }
      }

      let message = {
        id : 'incomingCallResponse',
        callResponse: 'accept',
        from : this.connectionId,
        sdpOffer : offerSdp
      };
      socket.emit('message', message);
    });
  });

}

function onErrorCalled(error) {
  console.error(error);
  socket.emit("call_reject", [app.talkId1]);
  restoreAfterCall(); // 20260729追加: リロードを待たずに画面を復帰させる
  setTimeout(function() {safeReload();}, 500); // 20260723変更: ネット復旧を確認してからリロード
}

// ===== テレビ電話アドレス一覧のオンライン絞り込み =====
// サーバー(tcp.js の clientsStatus)が 'app' / message:'clients_status' で
// 全UDIDの接続状況を返すので、それを使って
// 「オンライン(通話可能)な相手だけ」をアドレス一覧に表示する。
// 未接続は def.ECLIENT_STATUS.CLIENT_STATUS_NOT_CONNECT。
// 数値定義に依存しないよう、"未接続の値" をサーバー応答から学習して判定する。
var onlineStatusMap = {};          // UDID -> status文字列
var NOT_CONNECT_STATUS = null;     // 未接続を示すstatus値(応答から学習)
var onlineFilterReady = false;     // 一度でも応答を受けたか

function applyAddressListOnline(statusMap) {
  if (!statusMap) {
    return;
  }
  onlineStatusMap = statusMap;
  onlineFilterReady = true;

  // 未接続の値を学習する。サーバーは未接続時に
  // {status: <NOT_CONNECT>, udid: ...} だけの最小オブジェクトを返し、
  // 接続中は name / code などを含む完全な辞書を返す。
  // この差から未接続の status 値を特定する。
  if (NOT_CONNECT_STATUS === null) {
    for (var k in statusMap) {
      var v = statusMap[k];
      if (v && typeof v.name === 'undefined' && typeof v.status !== 'undefined') {
        NOT_CONNECT_STATUS = '' + v.status;
        break;
      }
    }
  }
  refreshAddressListOnline();
}

function isUdidOnline(udid) {
  // 家族(%F%)は端末ではなくグループ宛のため、常に表示する
  if (udid.indexOf('%F%') >= 0) {
    return true;
  }
  var v = onlineStatusMap[udid];
  if (typeof v === 'undefined') {
    return false;   // 一覧に無い＝接続していない
  }
  var st = '' + (typeof v === 'object' ? v.status : v);
  if (NOT_CONNECT_STATUS !== null) {
    return st !== NOT_CONNECT_STATUS;
  }
  // 未接続値が未学習の間は、name を持つ(=接続中の完全な辞書)かで判定
  return (typeof v === 'object' && typeof v.name !== 'undefined');
}

function refreshAddressListOnline() {
  // まだ一度も応答が無い間は絞り込まない(全件表示のまま)
  if (!onlineFilterReady) {
    return;
  }
  $('.address_list').each(function() {
    var $a = $(this);
    var udid = $a.attr('data-udid') || '';
    var $li = $a.closest('li');
    if (isUdidOnline(udid)) {
      $li.show();
    } else {
      $li.hide();
    }
  });
}

// ===== SpO2共有の受信(ドクター側) =====
// 通話中、患者側が socket.io('talk') の id2:'spo2share' で送ってくる
// SpO2/PR をポップアップに表示する。閉じるボタンで閉じた測定セッションは
// 再表示しない(spo2ShareClosedSession)。
var spo2ShareLastSession = '';
var spo2ShareClosedSession = '';
var spo2ShareLastReceiveAt = 0;
function receiveSpo2Share(info) {
  spo2ShareLastSession = '' + info.session;
  spo2ShareLastReceiveAt = Date.now();
  $('#spo2-popup-value').text(info.spo2);
  $('#spo2-popup-pr').text(info.pr);
  if (spo2ShareClosedSession === spo2ShareLastSession) {
    return;
  }
  if (!$('#spo2-popup').is(':visible')) {
    $('#spo2-popup').show();
    $('#spo2-popup-close').focus();
  }
}

// 共有が止まって(=患者の測定が自動停止して)60秒たったら自動で閉じる。
// 患者側の端末では spo2ShareLastReceiveAt は 0 のままなので影響しない。
setInterval(function() {
  if (spo2ShareLastReceiveAt > 0 &&
      $('#spo2-popup').is(':visible') &&
      Date.now() - spo2ShareLastReceiveAt >= 60 * 1000) {
    $('#spo2-popup').hide();
    spo2ShareLastReceiveAt = 0;
  }
}, 5 * 1000);

function talkStart() {
  closeTimeConfirm();/*20231121 通話スタート時に時計モードを終了する*/
  $('#my-video').removeClass('take-picture');/*通話開始時に自分カメラ映像を表示する(ami.v2.0.jsと同じ方式)*/
  $talkDiv.show()/*20231111 スタート時に通話画面を表示する*/
  tel01.pause();
  $open02.hide();
  $('#slide_images').hide();/*通話中はスライドショーを非表示にする(中身は消さない=復帰を確実にする)*/
  try { document.getElementById('message').stop(); } catch (e) {}/*通話中はメッセージ(マーキー)の流れを停止*/
  $('.hide1').hide();
  $('#end-li').show();
  $('#weather').hide();/*20230220*/
  setCallState(CALL_STATE.Talk);
  if ($('#info').is(':visible')) {
      $('#info').hide();
      $('#sidebar').show();
  }
  if ($('#info-section').is(':visible')) {
      $('#info-section').hide();
      $('#sidebar').show();
  }
  $('#end-btn').eq(0).focus();
  scheduleRemotePlayRetries();
}

// 通話終了後の画面復帰(20260729追加)
// safeReload() はサーバー到達を確認できるまでリロードしないため、
// 回線不調時はリロードされず、talkStart() が隠した状態のまま画面が
// 固まって見える問題があった。リロードに頼らず、ここで画面を元に戻す。
// リロードが成功すれば通常どおり再読込されるため、二重でも害はない。
function restoreAfterCall() {
  try {
    $('.hide1').show();          // メニュー(ホーム/テレビ電話/健康管理など)を戻す
    $('#end-li').hide();         // 通話終了ボタンを隠す(getInfoの通話中判定も解除される)
    $('#multi-div').hide();
    $('#hold-img').hide();
    $('#canvas').hide();
    $('#photo').hide();
    $talkDiv.show();
    $('#slide_images').show();   // スライドショー領域を再表示
    try { document.getElementById('message').start(); } catch (e) {} // メッセージの流れを再開
    if (app.weatherRegistered) {
      $('#weather').show();      // 天気を戻す(登録済みの場合のみ)
    }
    // スライドショーとメッセージは talkStart() で中身を消しているため、
    // getInfo() を即実行して再取得・再生成する。
    if (typeof getInfo === 'function') {
      getInfo();
    }
    $('#home-btn').eq(0).focus();
    setTimeout(function() {
      try { $('#home-btn').eq(0).focus(); } catch (e2) {}
    }, 200);
  } catch (e) {
    console.log('restoreAfterCall error', e);
  }
}

function stop(message) {
  console.log('stop');
  clearRemotePlayTimers();

  for (let k in peers) {
    disConnectPeer(k);
  }

  if (app.ws) {
    leaveRoom();
  }

  if (offcall) {
    $.ajax({
      url: 'http://localhost/offcall.php',
      type: "GET",
    })
      .done(function (data) {
        console.log(data);
      });
  }
  restoreAfterCall(); // 20260729追加: リロードを待たずに画面を復帰させる
  setTimeout(function() {safeReload();}, 500); // 20260723変更: ネット復旧を確認してからリロード
}

function callExt() {
  offcall = true;
  callLocalApi();
}

function receiveHangup(from) {
  console.log('receiveHangup', from, holdedId, app.talkId1, app.talkId2);
  if (holdedId === from) {
    stop(false);
    return;
  }
  if (app.talkId1 === from) {
    if (app.talkId2.length === 0) {
      stop(false);
    } else {

    }
  }
}

function receiveSafetyCheck() {
    $('#my-video').hide();
    let options = {
        localVideo : localVideo,
        remoteVideo : remoteVideo1,
        onicecandidate : onSockIceCandidate
    };

    let webRtcPeer = kurentoUtils.WebRtcPeer.WebRtcPeerSendonly(options, function(error) {
        if (error) {
            onErrorCalled(error);
            return;
        }

        this.connectionId = safetyCheckIds;
        peers[safetyCheckIds] = webRtcPeer;

        this.generateOffer(function(error, offerSdp) {
            if (error) {
                onErrorSafetyCheck(error);
                return;
            }

            if (candidatesQueue[this.connectionId]) {
                console.log('drain candidate');
                while(candidatesQueue[this.connectionId].length) {
                    let candidate = candidatesQueue[this.connectionId].shift();
                    this.addIceCandidate(candidate);
                }
            }

            let message = {
                id : 'incomingCallResponse',
                callResponse: 'accept',
                from : this.connectionId,
                sdpOffer : offerSdp
            };
            socket.emit('message', message);
        });
    });
}

function receiveSafetyCheckEnd(udid) {
  if (safetyCheckIds == udid) {
      restoreAfterCall(); // 20260729追加: リロードを待たずに画面を復帰させる
      setTimeout(function() {safeReload();}, 500); // 20260723変更: ネット復旧を確認してからリロード
  }
}

function onErrorSafetyCheck(error) {
    console.error(error);
    socket.emit("safety_check_error", [safetyCheckIds]);
    restoreAfterCall(); // 20260729追加: リロードを待たずに画面を復帰させる
    setTimeout(function() {safeReload();}, 500); // 20260723変更: ネット復旧を確認してからリロード
}

function onSockIceCandidate(candidate) {
  console.log('Local candidate' + JSON.stringify(candidate), this.connectionId);

  var message = {
    id : 'onIceCandidate',
    candidate : candidate,
    to: this.connectionId,
    name: this.connectionId
  };
  socket.emit('message', message);
}

/************************************************************************************************************************************
Socket
 */
function sockConnect() {
  socket = io.connect(app.url, { transports: ["websocket"] });
  sockEvent();
}

function sockEvent() {

  socket.on("connect", function() {
    console.log('sock connect');
    if (app.userID.length > 0) {
      socket.emit('login', {
        MYID: app.userID,
        USETYPE: "0",
        DELEGATOR: app.delegator,
        NAME: app.userName,
        GROUP: app.delegator + '_ROOM'
      });
    }
  });

  // ▼▼ ここに追加 ▼▼
  socket.on("disconnect", function(reason) {
    console.log('sock disconnect', reason);
    // デリゲータ再起動等で切断された場合、talk_endは届かないためここで確実に解放する
    if (Object.keys(peers).length > 0 || callState !== CALL_STATE.Stand) {
      tel01.pause();
      setCallState(CALL_STATE.Stand);
      stop(false);
    }
  });
  // ▲▲ ここまで ▲▲	

  socket.on("message", function(data) {
    var messageid = data.id;
    console.log(data);

    if (messageid === "callResponse") {
      onCallResponse(data);
    }
    else if (messageid === "startCommunication") {
      onStartCommunication(data);
    }
    else if (messageid === "iceCandidate") {
      onIceCandidate(data);
    }
  });

  socket.on("app", function(data) {
    console.log('app', data.message);

    if (data.message === 'from_server') {
      socket.emit('clients_status', {});/*初回はすぐ問い合わせて反映を早める*/
      setInterval(function () {socket.emit('clients_status', {});}, 10000);
    }
    else if (data.message === 'clients_status') {
      // サーバー(tcp.js clientsStatus)が10秒ごとに返す接続状況。
      // data.data = { UDID: {status:"n", udid:"...", ...}, ... }
      // status が未接続(CLIENT_STATUS_NOT_CONNECT)以外＝オンライン。
      applyAddressListOnline(data.data);
    }
    else if (data.message === 'status_change') {
      // 個別の状態変化通知。次のclients_statusを待たずに即反映する。
      if (data.info && data.info.MYID) {
        onlineStatusMap[data.info.MYID] = data.info.STATUS;
        refreshAddressListOnline();
      }
    }
    else if (data.message === 'call') {
      console.log('called', data);

      if (notreceive.includes(data.info.udid)) {
        socket.emit("call_reject", [data.info.udid]);
        return;
      }

      app.talkId1 = data.info.udid;
      setCallState(CALL_STATE.Called);
      called();
    }
    else if (data.message === 'talk_end') {
      console.log('talk_end', data.udid);
      receiveHangup(data.udid);
    }
    else if (data.message === 'hold') {
      if (callState === CALL_STATE.Talk) {
        if (app.talkId1 === data.udid) {
          holdedId = app.talkId1;
          setCallState(CALL_STATE.Holded);
          $remoteBg.addClass('bg-aqua');
          $holdImg.show();
          if (peers[app.talkId1]) {
            disConnectPeer(app.talkId1);
          }
        }
      }
    }
    else if (data.message === 'hold_clear') {
      let udid = data.info.udid;
      if (udid === holdedId) {
        holdedId = '';
        $holdImg.hide();
        $remoteBg.removeClass('bg-aqua');
        called();
      }
    }
    else if (data.message === 'request_photo') {
      receiveRequestPhoto(data);
    }
    else if (data.message === 'close_drawview') {
      $('#canvas').hide();
      $('#photo').hide();
      $remoteVideo1.show();
    }
    else if (data.message === 'talk') {
      let info = data.info;
      let talkId = info.id2;
      if (talkId === 'shareRecv') {
        shareReceive(info);
      }
      else if (talkId === 'shareRecvError') {

      }
      else if (talkId === 'shareUndo') {
        undo();
      }
      else if (talkId === 'shareEraseMode') {
        onShareEraseMode(info);
      }
      else if (talkId === 'spo2share') {
        receiveSpo2Share(info);
      }
       else if (talkId === 'checkmeshare') {
         receiveCheckmeShare(info);
      }
      else if (talkId === 'checkmeclose') {
        // 相手が閉じた → こちらも閉じる。
        // 測定側（グラフを出している側）なら自分のグラフ画面も閉じる。
        if (typeof closeCheckme === 'function') {
          try { closeCheckme(true); } catch (e) {}   // true = 送り返さない
        }
        closeCheckmeShare();
      }
      else if (talkId === 'draw') {
        receiveDrawEvent(info);
      }
      else if (talkId === 'threewayToCall') {
        let from = info.from;
        let to = info.to;
        console.log('threewayToCall', info);
        if (callState === CALL_STATE.Multi && (app.userID === from || app.userID === to)) {
          leaveRoom();
          app.talkId2 = '';
          $multiDiv.hide();
          $talkDiv.show();
          if (from === app.userID) {
            console.log('threewayToCall multi to multiTotalk');
            setCallState(CALL_STATE.MultiToTalk);
            app.talkId1 = to;
            setTimeout(function() {called();}, 1000);
          } else {
            console.log('threewayToCall multi to talk');
            setCallState(CALL_STATE.Talk);
            app.talkId1 = '';
            app.callId = from;
          }
        }
      }
      else {
        console.log(info);
      }
    }
    else if (data.message === 'threeway') {
      let info = data.info;

      if (callState === CALL_STATE.Holded && (holdedId === info.talkID1 || holdedId === info.talkID2)) {
        app.talkId1 = (holdedId === info.talkID1 ? info.talkID1 : info.talkID2);
        app.talkId2 = (holdedId === info.talkID1 ? info.talkID2 : info.talkID1);
        holdedId = '';
        app.threewayId = info.roomID;
        setCallState(CALL_STATE.Multi);
        $talkDiv.hide();
        $holdImg.hide();
        $multiDiv.show();
        $('#multiend-btn').focus();
        console.log('check threeway', app.threewayId, app.talkId1, app.talkId2);
        srConnect();
      } else if (callState === CALL_STATE.Talk && (app.talkId1 === info.talkID1 || app.talkId1 === info.talkID2)) {
        app.talkId2 = (app.talkId1 === info.talkID1 ? info.talkID2 : info.talkID1);
        holdedId = '';
        app.threewayId = info.roomID;
        setCallState(CALL_STATE.Multi);
        $talkDiv.hide();
        $holdImg.hide();
        $multiDiv.show();
        $('#multiend-btn').focus();
        console.log('check threeway2', app.threewayId, app.talkId1, app.talkId2);
        srConnect();
      } else {
        console.log('threeway error', holdedId, callState, info.talkID1, info.talkID2);
      }
    }
    else if (data.message === 'call_button') {
      app.callId = '@' + app.delegator + '_STAFF';
      doCall();
      callLocalApi();
      setTimeout(checkPowerApi, 3000);
    }
    else if (data.message === 'safety_check') {
        console.log(data.udid);
        var udid = data.udid;
        if (safetyCheckIds !== '') {
            socket.emit('safety_check_error', [udid]);
            return;
        }
        safetyCheckIds = udid;
        receiveSafetyCheck();
    }
    else if (data.message === 'safety_check_end') {
        var udid = data.udid;
        receiveSafetyCheckEnd(udid);
    }
  });

}

/************************************************************************************************************************************
 Socket Message
 */
function onCallResponse(data) {
  var response = data.response;

  if (response !== "accepted") {
    return;
  }
  var to = data.to;

  if (app.callId === '@' + app.delegator + '_STAFF') {
    app.callId = to;
  }
  // app.talkId1 = app.callId;
  console.log('call response', app.callId);

  let options = {
    localVideo : localVideo,
    remoteVideo : remoteVideo1,
    onicecandidate : onSockIceCandidate,
    mediaConstraints: piCallConstraints()
  };

  let webRtcPeer = kurentoUtils.WebRtcPeer.WebRtcPeerSendrecv(options,
    function(error) {
      if (error) {
        onErrorCallResponse(error);
        return;
      }

      this.connectionId = to;
      peers[to] = webRtcPeer;
      // 先に相手映像タグを表示してから SDP を処理する（初回黒画面対策）
      talkStart();

      this.processOffer(data.sdpOffer, function(error, sdp) {
        if (error) {
          onErrorCallResponse(error);
          return;
        }

        if (candidatesQueue[this.connectionId]) {
          console.log('drain candidate');
          while(candidatesQueue[this.connectionId].length) {
            let candidate = candidatesQueue[this.connectionId].shift();
            this.addIceCandidate(candidate);
          }
        }

        console.log('check send answer response ' + this.connectionId);
        let args = {
          id : 'answerResponse',
          from : this.connectionId,
          callResponse : 'accept',
          sdpAnswer : sdp
        };
        socket.emit('message', args);

        if (app.callId.length > 0) {
          app.talkId1 = app.callId;
          app.callId = '';
          console.log('check app.talkId1 => [' + app.talkId1 + ']');
        }
        ensureRemoteVideoPlaying();
      });
    });
}

function onErrorCallResponse(error) {
  console.error(error);
  socket.emit("call_cancel", [app.callId]);
  setCallState(CALL_STATE.Stand);
  app.callId = '';
}

function onStartCommunication(data) {
  let to = data.to;
  if (peers[to]) {

  }
  peers[to].processAnswer(data.sdpAnswer);
  if (safetyCheckIds == to) {
    return;
  }
  if (callState !== CALL_STATE.MultiToTalk) {
    socket.emit('call_accept', [to]);
  }
  talkStart();
  callExt();
}

function onIceCandidate(data) {
  if (!data.from) {
    return;
  }
  var from = data.from;
  console.log('iceCandidate', from);
  if (peers[from]) {
    console.log('add icecandidate ', from);
    peers[from].addIceCandidate(data.candidate);
  } else {
    console.log('queue icecandidate');
    if (!candidatesQueue[from]) {
      candidatesQueue[from] = [];
    }
    candidatesQueue[from].push(data.candidate);
  }
}

$(function() {
  window.onbeforeunload = function() {
    socket.disconnect();
    if (ws) {
      ws.close();
    }
  };
  init();
});
// 通話中、相手（測定側）から送られてくる Checkme のデータを表示する。
// 数値だけでなく波形も受け取り、測定側と同じ画面で描画する。
// 波形は 400ms ごと・間引き済みのため回線負荷は小さい。
function toNumArray(v) {
  if (typeof v === 'string') {
    try { v = JSON.parse(v); } catch (e) { return null; }
  }
  if (Array.isArray(v)) return v;
  if (v && typeof v === 'object') {
    var out = [];
    for (var i = 0; i < 20000; i++) {
      if (v[i] === undefined) break;
      var n = Number(v[i]);
      if (!isNaN(n)) out.push(n);
    }
    return out.length ? out : null;
  }
  return null;
}

function postCheckmeRemote(payload) {
  var fr = document.getElementById('checkme-remote-frame');
  if (!fr || !fr.contentWindow) return;
  if (!window._checkmeRemoteReady) {
    window._checkmeRemoteQueue = window._checkmeRemoteQueue || [];
    window._checkmeRemoteQueue.push(payload);
    return;
  }
  try { fr.contentWindow.postMessage(payload, '*'); } catch (e) {}
}

// 通話中、相手（測定側）から送られてくる Checkme のデータを表示する。
// 数値だけでなく波形も受け取り、測定側と同じ画面で描画する。
// 波形は 400ms ごと・間引き済みのため回線負荷は小さい。
function receiveCheckmeShare(info) {
  // 測定側が「閉じる」を押した合図（closed:'1'）。
  // 波形と同じ実績ある経路で届くため確実。受けたら即座に閉じる。
  if (info && info.closed === '1') {
    if (typeof window.closeCheckme === 'function') {
      try { window.closeCheckme(true); } catch (e) {}   // 測定側の画面（あれば）
    }
    closeCheckmeShare();                                 // 受信側の画面
    return;
  }

  var wrap = document.getElementById('checkme-remote-wrap');

  // 初回受信時に、受信専用モードの iframe を作って表示する
  if (!wrap) {
    wrap = document.createElement('div');
    wrap.id = 'checkme-remote-wrap';
    wrap.style.cssText =
      'position:fixed; left:5px; bottom:5px; width:43vw; aspect-ratio:16 / 9;' +
      'z-index:9998;';
    wrap.innerHTML =
      '<iframe id="checkme-remote-frame" frameborder="0" allowtransparency="true" ' +
      'src="./checkme_monitor.php?mode=remote" ' +
      'style="width:100%; height:100%; border:0; background:transparent;"></iframe>' +
      // 閉じるボタン（リモコン操作のため ul>li>a 構造。押すと相手側も閉じる）
      '<ul id="checkme-remote-ctl" style="list-style:none; margin:0; padding:0;' +
      'position:absolute; right:10px; top:8px; z-index:2;">' +
      '<li><a id="checkme-remote-close" href="javascript:;" ' +
      'style="display:inline-block; background:#1e9dfa; color:#fff;' +
      'text-decoration:none; border-radius:5px; padding:6px 18px; font-size:16px;">' +
      '閉じる</a></li></ul>';
    document.body.appendChild(wrap);
    window._checkmeRemoteReady = false;
    window._checkmeRemoteQueue = [];
    var frNew = document.getElementById('checkme-remote-frame');
    if (frNew) {
      frNew.addEventListener('load', function () {
        window._checkmeRemoteReady = true;
        var q = window._checkmeRemoteQueue || [];
        window._checkmeRemoteQueue = [];
        q.forEach(function (p) { postCheckmeRemote(p); });
      });
    }

    // 閉じる：自分の画面を閉じ、測定側（相手）にも閉じるよう通知する。
    // 通知は波形と同じ checkmeshare 経路（closed フラグ）で送る。
    var btn = document.getElementById('checkme-remote-close');
    if (btn) {
      btn.addEventListener('click', function () {
        try {
          if (typeof socket !== 'undefined' && socket && app.talkId1 && app.talkId1.length > 0) {
            var closeMsg = { id2: 'checkmeshare', closed: '1', to: app.talkId1 };
            socket.emit('talk', closeMsg);
            setTimeout(function () { try { socket.emit('talk', closeMsg); } catch (e) {} }, 300);
          }
        } catch (e) {}
        closeCheckmeShare();
      });
    }
  }
  wrap.style.display = 'block';

  // 共有グラフが表示されている間は、メニューのCheckmeボタンを「閉じる」にする
  // （測定側と同じ見た目・同じ操作感にするため。検証NO.8対応）
  setCheckmeButtonText('閉じる');

  var payload = {
    type: 'checkme-remote-data',
    hr:   info.hr   ? parseInt(info.hr, 10)   : null,
    spo2: info.spo2 ? parseInt(info.spo2, 10) : null,
    pr:   info.pr   ? parseInt(info.pr, 10)   : null,
    pi:   info.pi   ? parseFloat(info.pi)     : null,
    ecg:   toNumArray(info.ecg),
    pleth: toNumArray(info.pleth)
  };
  postCheckmeRemote(payload);

  // 一定時間データが来なければ閉じる（通話終了後に残らないように）
  clearTimeout(window._checkmeRemoteTimer);
  window._checkmeRemoteTimer = setTimeout(function () {
    closeCheckmeShare();
  }, 60000);
}

// メニューのCheckmeボタン（通常・通話中の両方）の表示文字を切り替える
function setCheckmeButtonText(text) {
  var ids = ['checkme-btn', 'checkme-call-btn'];
  for (var i = 0; i < ids.length; i++) {
    var b = document.getElementById(ids[i]);
    if (b) { b.textContent = text; }
  }
}

// 測定側が「閉じる」を押したときに、こちらの表示も閉じる。
// 60秒待たずに即座に消えるようにするため、通話経路で通知を受けて呼ばれる。
function closeCheckmeShare() {
  clearTimeout(window._checkmeRemoteTimer);
  window._checkmeRemoteReady = false;
  window._checkmeRemoteQueue = [];
  var w = document.getElementById('checkme-remote-wrap');
  if (w) {
    w.style.display = 'none';
    var fr = document.getElementById('checkme-remote-frame');
    if (fr) { fr.src = 'about:blank'; }   // 描画を止めて資源を解放する
    w.parentNode.removeChild(w);          // 次回は作り直す
  }
  // 自分側の測定画面を開いていない限り、ボタン表示を「Checkme」に戻す
  var localOpen = false;
  try { localOpen = (localStorage.getItem('checkmeOpen') === '1'); } catch (e) {}
  if (!localOpen) { setCheckmeButtonText('Checkme'); }
}

// メニューのCheckmeボタンから共有グラフを閉じるときに使う
// （index.php から呼ばれる。相手側にも閉じるよう通知する）
function closeRemoteCheckme() {
  try {
    if (typeof socket !== 'undefined' && socket && app.talkId1 && app.talkId1.length > 0) {
      var closeMsg = { id2: 'checkmeshare', closed: '1', to: app.talkId1 };
      socket.emit('talk', closeMsg);
      setTimeout(function () { try { socket.emit('talk', closeMsg); } catch (e) {} }, 300);
    }
  } catch (e) {}
  closeCheckmeShare();
}
window.closeRemoteCheckme = closeRemoteCheckme;