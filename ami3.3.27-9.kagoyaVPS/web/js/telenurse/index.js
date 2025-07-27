
var localVideo = document.getElementById('local_video');
//var remoteVideo = document.getElementById('remote_video');
var localStream = null;
//var peerConnection = null;
//var textForSendSdp = document.getElementById('text_for_send_sdp');
//var textToReceiveSdp = document.getElementById('text_for_receive_sdp');
// ---- for multi party -----
var peerConnections = [];
//var remoteStreams = [];
var remoteVideos = [];
const MAX_CONNECTION_COUNT = 3;
// --- multi video ---
var container = document.getElementById('container');
_assert('container', container);
// --- prefix -----
navigator.getUserMedia  = navigator.getUserMedia    || navigator.webkitGetUserMedia ||
  navigator.mozGetUserMedia || navigator.msGetUserMedia;
RTCPeerConnection = window.RTCPeerConnection || window.webkitRTCPeerConnection || window.mozRTCPeerConnection;
RTCSessionDescription = window.RTCSessionDescription || window.webkitRTCSessionDescription || window.mozRTCSessionDescription;
/*---
 // -------- websocket ----
 // please use node.js app
 //
 // or you can use chrome app (only work with Chrome)
 //  https://chrome.google.com/webstore/detail/simple-message-server/bihajhgkmpfnmbmdnobjcdhagncbkmmp
 //
 var wsUrl = 'ws://localhost:3001/';
 var ws = new WebSocket(wsUrl);
 ws.onopen = function(evt) {
 console.log('ws open()');
 };
 ws.onerror = function(err) {
 console.error('ws onerror() ERR:', err);
 };
 ws.onmessage = function(evt) {
 console.log('ws onmessage() data:', evt.data);
 var message = JSON.parse(evt.data);
 if (message.type === 'offer') {
 // -- got offer ---
 console.log('Received offer ...');
 textToReceiveSdp.value = message.sdp;
 var offer = new RTCSessionDescription(message);
 setOffer(offer);
 }
 else if (message.type === 'answer') {
 // --- got answer ---
 console.log('Received answer ...');
 textToReceiveSdp.value = message.sdp;
 var answer = new RTCSessionDescription(message);
 setAnswer(answer);
 }
 else if (message.type === 'candidate') {
 // --- got ICE candidate ---
 console.log('Received ICE candidate ...');
 var candidate = new RTCIceCandidate(message.ice);
 console.log(candidate);
 addIceCandidate(candidate);
 }
 };
 --*/
// ----- use socket.io ---
var socket = io.connect();
var room = getRoomName();
socket.on('connect', function(evt) {
  console.log('socket.io connected. enter room=' + room );
  socket.emit('enter', room);
});
socket.on('message', function(message) {
  console.log('message:', message);
  var fromId = message.from;
  if (message.type === 'offer') {
    // -- got offer ---
    console.log('Received offer ...');
    var offer = new RTCSessionDescription(message);
    setOffer(fromId, offer);
  }
  else if (message.type === 'answer') {
    // --- got answer ---
    console.log('Received answer ...');
    var answer = new RTCSessionDescription(message);
    setAnswer(fromId, answer);
  }
  else if (message.type === 'candidate') {
    // --- got ICE candidate ---
    console.log('Received ICE candidate ...');
    var candidate = new RTCIceCandidate(message.ice);
    console.log(candidate);
    addIceCandidate(fromId, candidate);
  }
  else if (message.type === 'call me') {
    if (! isReadyToConnect()) {
      console.log('Not ready to connect, so ignore');
      return;
    }
    else if (! canConnectMore()) {
      console.warn('TOO MANY connections, so ignore');
    }
    if (isConnectedWith(fromId)) {
      // already connnected, so skip
      console.log('already connected, so ignore');
    }
    else {
      // connect new party
      makeOffer(fromId);
    }
  }
  else if (message.type === 'bye') {
    if (isConnectedWith(fromId)) {
      stopConnection(fromId);
    }
  }
});
socket.on('user disconnected', function(evt) {
  console.log('====user disconnected==== evt:', evt);
  var id = evt.id;
  if (isConnectedWith(id)) {
    stopConnection(id);
  }
});
// --- broadcast message to all members in room
function emitRoom(msg) {
  socket.emit('message', msg);
}
function emitTo(id, msg) {
  msg.sendto = id;
  socket.emit('message', msg);
}
// -- room名を取得 --
function getRoomName() { // たとえば、 URLに  ?roomname  とする
  var url = document.location.href;
  var args = url.split('?');
  if (args.length > 1) {
    var room = args[1];
    if (room != '') {
      return room;
    }
  }
  return '_testroom';
}
// ---- for multi party -----
function isReadyToConnect() {
  if (localStream) {
    return true;
  }
  else {
    return false;
  }
}
// --- RTCPeerConnections ---
function getConnectionCount() {
  return peerConnections.length;
}
function canConnectMore() {
  return (getConnectionCount() < MAX_CONNECTION_COUNT);
}
function isConnectedWith(id) {
  if (peerConnections[id])  {
    return true;
  }
  else {
    return false;
  }
}
function addConnection(id, peer) {
  _assert('addConnection() peer', peer);
  _assert('addConnection() peer must NOT EXIST', (! peerConnections[id]));
  peerConnections[id] = peer;
}
function getConnection(id) {
  var peer = peerConnections[id];
  _assert('getConnection() peer must exist', peer);
  return peer;
}
function deleteConnection(id) {
  _assert('deleteConnection() peer must exist', peerConnections[id]);
  delete peerConnections[id];
}
function stopConnection(id) {
  detachVideo(id);
  if (isConnectedWith(id)) {
    var peer = getConnection(id);
    peer.close();
    deleteConnection(id);
  }
}
function stopAllConnection() {
  for (var id in peerConnections) {
    stopConnection(id);
  }
}
// --- video elements ---
function attachVideo(id, stream) {
  var video = addRemoteVideoElement(id);
  playVideo(video, stream);
  video.volume = 1.0;
}
function detachVideo(id) {
  var video = getRemoteVideoElement(id);
  pauseVideo(video);
  deleteRemoteVideoElement(id);
}

function isRemoteVideoAttached(id) {
  if (remoteVideos[id]) {
    return true;
  }
  else {
    return false;
  }
}
function addRemoteVideoElement(id) {
  _assert('addRemoteVideoElement() video must NOT EXIST', (! remoteVideos[id]));
  var video = createVideoElement('remote_video_' + id);
  remoteVideos[id] = video;
  return video;
}
function getRemoteVideoElement(id) {
  var video = remoteVideos[id];
  _assert('getRemoteVideoElement() video must exist', video);
  return video;
}
function deleteRemoteVideoElement(id) {
  _assert('deleteRemoteVideoElement() stream must exist', remoteVideos[id]);
  removeVideoElement('remote_video_' + id);
  delete remoteVideos[id];
}
function createVideoElement(elementId) {
  var video = document.createElement('video');
  video.width = '240';
  video.height = '180';
  video.id = elementId;
  video.style.border = 'solid black 1px';
  video.style.margin = '2px';
  container.appendChild(video);
  return video;
}
function removeVideoElement(elementId) {
  var video = document.getElementById(elementId);
  _assert('removeVideoElement() video must exist', video);
  container.removeChild(video);
  return video;
}
// ---------------------- media handling -----------------------
// start local video
function startVideo() {
  getDeviceStream({video: true, audio: true}) // audio: false <-- ontrack once, audio:true --> ontrack twice!!
    .then(function (stream) { // success
      localStream = stream;
      playVideo(localVideo, stream);
    }).catch(function (error) { // error
    console.error('getUserMedia error:', error);
    return;
  });
}
// stop local video
function stopVideo() {
  pauseVideo(localVideo);
  stopLocalStream(localStream);
  localStream = null;
}
function stopLocalStream(stream) {
  var tracks = stream.getTracks();
  if (! tracks) {
    console.warn('NO tracks');
    return;
  }

  for (var track in tracks) {
    track.stop();
  }
}

function getDeviceStream(option) {
  if ('getUserMedia' in navigator.mediaDevices) {
    console.log('navigator.mediaDevices.getUserMadia');
    return navigator.mediaDevices.getUserMedia(option);
  }
  else {
    console.log('wrap navigator.getUserMadia with Promise');
    return new Promise(function(resolve, reject){
      navigator.getUserMedia(option,
        resolve,
        reject
      );
    });
  }
}
function playVideo(element, stream) {
  if ('srcObject' in element) {
    element.srcObject = stream;
  }
  else {
    element.src = window.URL.createObjectURL(stream);
  }
  element.play();
  element.volume = 0;
}
function pauseVideo(element) {
  element.pause();
  if ('srcObject' in element) {
    element.srcObject = null;
  }
  else {
    if (element.src && (element.src !== '') ) {
      window.URL.revokeObjectURL(element.src);
    }
    element.src = '';
  }
}
/*--
 // ----- hand signaling ----
 function onSdpText() {
 var text = textToReceiveSdp.value;
 if (peerConnection) {
 console.log('Received answer text...');
 var answer = new RTCSessionDescription({
 type : 'answer',
 sdp : text,
 });
 setAnswer(answer);
 }
 else {
 console.log('Received offer text...');
 var offer = new RTCSessionDescription({
 type : 'offer',
 sdp : text,
 });
 setOffer(offer);
 }
 textToReceiveSdp.value ='';
 }
 --*/

function sendSdp(id, sessionDescription) {
  console.log('---sending sdp ---');
  /*---
   textForSendSdp.value = sessionDescription.sdp;
   textForSendSdp.focus();
   textForSendSdp.select();
   ----*/
  var message = { type: sessionDescription.type, sdp: sessionDescription.sdp };
  console.log('sending SDP=' + message.type);
  //ws.send(message);
  emitTo(id, message);
}
function sendIceCandidate(id, candidate) {
  console.log('---sending ICE candidate ---');
  var obj = { type: 'candidate', ice: candidate };
  //var message = JSON.stringify(obj);
  //console.log('sending candidate=' + message);
  //ws.send(message);
  emitTo(id, obj);
}
// ---------------------- connection handling -----------------------
function prepareNewConnection(id) {
  var pc_config = {"iceServers":[
    {"urls": "stun:stun.l.google.com:19302"},
    {
      url: 'turn:numb.viagenie.ca',
      credential: 'muazkh',
      username: 'webrtc@live.com'
    }
  ]};
  var peer = new RTCPeerConnection(pc_config);
  // --- on get remote stream ---
  if ('ontrack' in peer) {
    peer.ontrack = function(event) {
      var stream = event.streams[0];
      console.log('-- peer.ontrack() stream.id=' + stream.id);
      if (isRemoteVideoAttached(id)) {
        console.log('stream already attached, so ignore');
      }
      else {
        //playVideo(remoteVideo, stream);
        attachVideo(id, stream);
      }
    };
  }
  else {
    peer.onaddstream = function(event) {
      var stream = event.stream;
      console.log('-- peer.onaddstream() stream.id=' + stream.id);
      //playVideo(remoteVideo, stream);
      attachVideo(id, stream);
    };
  }
  // --- on get local ICE candidate
  peer.onicecandidate = function (evt) {
    if (evt.candidate) {
      console.log(evt.candidate);
      // Trickle ICE の場合は、ICE candidateを相手に送る
      sendIceCandidate(id, evt.candidate);
      // Vanilla ICE の場合には、何もしない
    } else {
      console.log('empty ice event');
      // Trickle ICE の場合は、何もしない

      // Vanilla ICE の場合には、ICE candidateを含んだSDPを相手に送る
      //sendSdp(id, peer.localDescription);
    }
  };
  // --- when need to exchange SDP ---
  peer.onnegotiationneeded = function(evt) {
    console.log('-- onnegotiationneeded() ---');
  };
  // --- other events ----
  peer.onicecandidateerror = function (evt) {
    console.error('ICE candidate ERROR:', evt);
  };
  peer.onsignalingstatechange = function() {
    console.log('== signaling status=' + peer.signalingState);
  };
  peer.oniceconnectionstatechange = function() {
    console.log('== ice connection status=' + peer.iceConnectionState);
    if (peer.iceConnectionState === 'disconnected') {
      console.log('-- disconnected --');
      //hangUp();
      stopConnection(id);
    }
  };
  peer.onicegatheringstatechange = function() {
    console.log('==***== ice gathering state=' + peer.iceGatheringState);
  };

  peer.onconnectionstatechange = function() {
    console.log('==***== connection state=' + peer.connectionState);
  };
  peer.onremovestream = function(event) {
    console.log('-- peer.onremovestream()');
    //pauseVideo(remoteVideo);
    deleteRemoteStream(id);
    detachVideo(id);
  };


  // -- add local stream --
  if (localStream) {
    console.log('Adding local stream...');
    peer.addStream(localStream);
  }
  else {
    console.warn('no local stream, but continue.');
  }
  return peer;
}
function makeOffer(id) {
  _assert('makeOffer must not connected yet', (! isConnectedWith(id)) );
  peerConnection = prepareNewConnection(id);
  addConnection(id, peerConnection);
  peerConnection.createOffer()
    .then(function (sessionDescription) {
      console.log('createOffer() succsess in promise');
      return peerConnection.setLocalDescription(sessionDescription);
    }).then(function() {
    console.log('setLocalDescription() succsess in promise');
    // -- Trickle ICE の場合は、初期SDPを相手に送る --
    sendSdp(id, peerConnection.localDescription);
    // -- Vanilla ICE の場合には、まだSDPは送らない --
  }).catch(function(err) {
    console.error(err);
  });
}
function setOffer(id, sessionDescription) {
  /*
   if (peerConnection) {
   console.error('peerConnection alreay exist!');
   }
   */
  _assert('setOffer must not connected yet', (! isConnectedWith(id)) );
  var peerConnection = prepareNewConnection(id);
  addConnection(id, peerConnection);

  peerConnection.setRemoteDescription(sessionDescription)
    .then(function() {
      console.log('setRemoteDescription(offer) succsess in promise');
      makeAnswer(id);
    }).catch(function(err) {
    console.error('setRemoteDescription(offer) ERROR: ', err);
  });
}

function makeAnswer(id) {
  console.log('sending Answer. Creating remote session description...' );
  var peerConnection = getConnection(id);
  if (! peerConnection) {
    console.error('peerConnection NOT exist!');
    return;
  }

  peerConnection.createAnswer()
    .then(function (sessionDescription) {
      console.log('createAnswer() succsess in promise');
      return peerConnection.setLocalDescription(sessionDescription);
    }).then(function() {
    console.log('setLocalDescription() succsess in promise');
    // -- Trickle ICE の場合は、初期SDPを相手に送る --
    sendSdp(id, peerConnection.localDescription);
    // -- Vanilla ICE の場合には、まだSDPは送らない --
  }).catch(function(err) {
    console.error(err);
  });
}
function setAnswer(id, sessionDescription) {
  var peerConnection = getConnection(id);
  if (! peerConnection) {
    console.error('peerConnection NOT exist!');
    return;
  }
  peerConnection.setRemoteDescription(sessionDescription)
    .then(function() {
      console.log('setRemoteDescription(answer) succsess in promise');
    }).catch(function(err) {
    console.error('setRemoteDescription(answer) ERROR: ', err);
  });
}
// --- tricke ICE ---
function addIceCandidate(id, candidate) {
  var peerConnection = getConnection(id);
  if (peerConnection) {
    peerConnection.addIceCandidate(candidate);
  }
  else {
    console.error('PeerConnection not exist!');
    return;
  }
}

// start PeerConnection
function connect() {
  /*
   debugger; // SHOULD NOT COME HERE
   if (! peerConnection) {
   console.log('make Offer');
   makeOffer();
   }
   else {
   console.warn('peer already exist.');
   }
   */
  if (! isReadyToConnect()) {
    console.warn('NOT READY to connect');
  }
  else if (! canConnectMore()) {
    console.log('TOO MANY connections');
  }
  else {
    callMe();
  }
}
// close PeerConnection
function hangUp() {
  /*
   if (peerConnection) {
   console.log('Hang up.');
   peerConnection.close();
   peerConnection = null;
   pauseVideo(remoteVideo);
   }
   else {
   console.warn('peer NOT exist.');
   }
   */
  emitRoom({ type: 'bye' });
  stopAllConnection();
}
// ---- multi party --
function callMe() {
  emitRoom({type: 'call me'});
}