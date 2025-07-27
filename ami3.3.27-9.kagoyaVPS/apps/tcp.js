var utils = require('./utils.js');
var app = require('./app.js');
var def = require('./define.js');
var request = require('request');
var socketio = require('socket.io');

var tcp = {

  listen: function(server) {
    var that = this;
    var io = socketio(server);

    io.sockets.on('connection', function(socket) {
      //console.log('socket connect');

      socket.on('disconnect', function() {
        that.disconnect(this);
      });

      socket.on('view_log', function(data) {
        this.join('log');
      });

      socket.on('login', function(data) {
        that.login(this, data);
      });

      socket.on('willdisconnect', function(data) {
        console.log('willdisconnect', data);
        that.logout(this);
      });

      socket.on('client_info', function(data) {
        that.clientInfo(this, data);
      });

      socket.on('clients_status', function(data) {
        that.clientsStatus(this, data);
      });

      socket.on('msg', function(data) {
        that.msg(this, data);
      });

      socket.on('called_check', function(data) {
        that.calledCheck(this, data);
      });

      socket.on('call', function(data) {
        that.callRequest(this, data);
      });

      socket.on('pccall', function(data) {
        that.pcCallRequest(this, data);
      });

      socket.on('call_cancel', function(data) {
        that.callCancel(this, data);
      });

      socket.on('call_reject', function(data) {
        that.callReject(this, data);
      });

      socket.on('call_not_auth', function(data) {
        that.callNotAuth(this, data);
      });

      socket.on('call_accept', function(data) {
        that.callAccept(this, data);
      });

      socket.on('call?', function(data) {
        that.isCallRequest(this, data);
      });

      socket.on('talk_end', function(data) {
        that.talkEnd(this, data);
      });

      socket.on('hangup', function(data) {
        that.hangup(this, data);
      });

      socket.on('hold', function(data) {
        that.callHold(this, data);
      });

      socket.on('hold_clear', function(data) {
        that.callHoldClear(this, data);
      });

      socket.on('hold_end', function(data) {
        that.holdEnd(this, data);
      });

      socket.on('holded_end', function(data) {
        that.holdedEnd(this, data);
      });

      socket.on('camera_mute', function(data) {
        that.emitToTalkTo(this, "camera_mute");
      });

      socket.on('threeway_call', function(data) {
        that.callThreeway(this, data);
      });

      socket.on('to_threeway', function(data) {
        that.toThreeway(this, data);
      });

      socket.on('request_record', function(data) {
        that.requestRecord(this, data);
      });

      socket.on('request_record_reject', function(data) {
        that.requestRecordReject(this, data);
      });

      socket.on('request_record_accept', function(data) {
        that.requestRecordAccept(this, data);
      });

      socket.on('record_stop', function(data) {
        that.recordStop(this, data);
      });

      socket.on('change_camera', function(data) {
        that.emitToTalkTo(this, "change_camera");
      });

      socket.on('request_photo', function(data) {
        that.requestPhoto(this, data);
      });

      socket.on('photo_image', function(data) {
        that.photoImage(this, data);
      });

      socket.on('photo_receive', function(data) {
        that.emitToTalkTo(this, "photo_receive");
      });

      socket.on('close_drawview', function(data) {
        that.emitToTalkTo(this, "close_drawview");
      });

      socket.on('safety_check', function(data) {
        that.safetyCheck(this, data);
      });

      socket.on('safety_check_start', function(data) {
        that.safetyCheckStart(this, data);
      });

      socket.on('safety_check_error', function(data) {
        that.safetyCheckError(this, data);
      });

      socket.on('safety_check_stop', function(data) {
        that.safetyCheckStop(this, data);
      });

      socket.on('safety_check_end', function(data) {
        that.safetyCheckEnd(this, data);
      });

      socket.on('live_check', function(data) {
        that.liveCheck(this, data);
      });

      socket.on('live_check_error', function(data) {
        that.liveCheckError(this, data);
      });

      socket.on('live_check_end', function(data) {
        that.liveCheckEnd(this, data);
      });

      socket.on('draw', function(data) {
        that.draw(this, data);
      });

      socket.on('talk', function(data) {
        that.talk(this, data);
      });

      socket.on('viewcan_image', function(data) {
        that.viewcanImage(this, data);
      });

      socket.on('message', function(message) {
        //console.log('message', message);
        if (message.id === 'call') {
          that.messageCall(this, message);
        }
        else if (message.id === 'incomingCallResponse') {
          that.messageIncomingCallResponse(this, message);
        }
        else if (message.id === 'answerResponse') {
          that.messageAnswerResponse(this, message);
        }
        else if (message.id === 'onIceCandidate') {
          that.messageOnIceCandidate(this, message);
        }
      });

    });

    return io;
  },

  msg: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }
    var to = data.to;
    console.log('msg ? ' + client.udid + ' -> ' + to);

    var toClient = app.getClient(to);
    if (toClient) {
      toClient.socket.emit("app", {message: "msg", info: data});
    }
  },

  messageCall: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    client.sdpOffer = data.sdpOffer;

    var to = data.to;
    console.log('call request ' + client.udid + ' -> ' + to);

    var message = {
      id: 'incomingCall',
      from: data.from
    };

    var toClient;

    if (to.substring(0, 1) == '@') {
      // グループ呼び出し
      var toGroup = to.substring(1);

      app.groupcast(toGroup, "message", message);
      for (var id in app.clients) {
        if (id == socket.id) {
          continue;
        }
        toClient = app.clients[id];
        if (toClient.group == toGroup) {
          client.callTo.push(toClient.udid);
        }
      }
      client.callToGroup = toGroup;
      client.status = def.ECLIENT_STATUS.CLIENT_STATUS_CALL;
      app.groupCalling[client.udid] = toGroup;

      app.pushToGroup(toGroup, "【" + client.udid + "】" + (client.name.length ? client.name + 'さんから' : '') + "緊急呼び出し");
      return;
    }

    var callOK = 0;
    toClient = app.getClient(to);

    //console.log('call to client:', toClient);

    if (toClient == null) {
      callOK = 1;
    } else if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_CALL) {
      callOK = 2;
    } else if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_TALK) {
      callOK = 3;
    } else if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_MULTI) {
      callOK = 3;
    } else if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_HOLD) {
      callOK = 3;
    } else if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_HOLDED) {
      callOK = 3;
    } else if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_STAND) {
      client.status = def.ECLIENT_STATUS.CLIENT_STATUS_CALL;
      app.groupcast(client.code, 'status_change', {"MYID" : client.udid, "STATUS": client.status.toString()});
      app.groupcast(client.code, 'app', {message: "status_change", info: {"MYID" : client.udid, "STATUS": client.status.toString()}});
      toClient.socket.emit("message", message);
      client.callTo.push(toClient.udid);
    }

    if (callOK > 0) {
      socket.emit("app", {message: 'not_connect', info: callOK.toString()});
      socket.emit('not_connect', callOK.toString());
    }
  },

  messageIncomingCallResponse: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    var toClient = app.getClient(data.from);
    if (toClient == null) {
      return;
    }

    if (data.callResponse === 'accept') {
      var message = {
        id: 'startCommunication',
        sdpAnswer: toClient.sdpOffer
      };
      //client.socket.emit('message', message);


      message = {
        id: 'callResponse',
        response : 'accepted',
        sdpOffer: data.sdpOffer,
        to: client.udid
      };
      toClient.socket.emit('message', message);
    }
  },

  messageAnswerResponse: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    var toClient = app.getClient(data.from);
    if (toClient == null) {
      return;
    }

    if (data.callResponse === 'accept') {
      var message = {
        id: 'startCommunication',
        sdpAnswer: data.sdpAnswer,
        to: client.udid
      };
      toClient.socket.emit('message', message);
    }
  },

  messageOnIceCandidate: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }
    var message = {
      id: 'iceCandidate',
      candidate: data.candidate,
      from: client.udid
    };

    var toClient = app.getClient(data.to);
    if (toClient != null) {
      toClient.socket.emit('message', message);
    }
  },

  disconnect: function(socket) {
    var toClient;
    if (app.clients[socket.id]) {
      var client = app.clients[socket.id];
      var udid = client.udid;

      //socket.broadcast.emit("status_change", {"MYID" : udid, "STATUS": def.ECLIENT_STATUS.CLIENT_STATUS_NOT_CONNECT.toString()});
      app.broadcast("status_change", {"MYID" : udid, "STATUS": def.ECLIENT_STATUS.CLIENT_STATUS_NOT_CONNECT.toString()});
      app.broadcast('app', {message: "status_change", info: {"MYID" : udid, "STATUS": def.ECLIENT_STATUS.CLIENT_STATUS_NOT_CONNECT.toString()}});
      console.log("disconnected:", udid);
      for (var i = 0; i < client.talkTo.length; i++) {
        var to = client.talkTo[i].udid;
        toClient = app.getClient(to);
        if (toClient) {
          this.doTalkEnd(udid, toClient);
          this.postRecordLog(toClient.udid, toClient.record);
        }
      }
      if (client.hasHoldTo()) {
        this.postTalkLog(udid, client.holdTo);
        toClient = app.getClient(client.holdTo.udid);
        if (toClient) {
          this.doHoldEnd(client, toClient);
        }
      }
      if (client.hasHoldFrom()) {
        this.postTalkLog(udid, client.holdFrom);
        toClient = app.getClient(client.holdFrom.udid);
        if (toClient) {
          this.doHoldedEnd(client, toClient);
        }
      }

      this.postRecordLog(client.udid, client.record);
      delete app.clients[socket.id];
      delete app.groupCalling[udid];
    }
  },

  doDisconnect: function(socketId) {
    var client = app.clients[socketId];
    var udid = client.udid;
    app.broadcast("status_change", {"MYID" : udid, "STATUS": def.ECLIENT_STATUS.CLIENT_STATUS_NOT_CONNECT.toString()});
    delete app.clients[socketId];
  },

  postTalkLog: function(udid, talkInfo) {
    //console.log('postTalkLog', udid, talkInfo);
    if (!talkInfo.udid) {
      return;
    }
    var client = app.getClient(udid);
    var name = (client == null ? '' : client.name);
    var toClient = app.getClient(talkInfo.udid);
    var toName = (toClient == null ? '' : toClient.name);

    process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
    var endTime = utils.dateFormat(new Date(), 'yyyy-mm-dd H:i:s');
    var options = {
      url: def.AMI_DOMAIN + "delegator/add_talk_log",
      method: 'POST',
      headers: {
        "Content-type": "application/json"
      },
      json: true,
      form: {
        "token": app.amiToken,
        "id": app.masterId,
        "udid1": (talkInfo.receive == '1' ? talkInfo.udid : udid),
        "name1": (talkInfo.receive == '1' ? toName : name),
        "udid2": (talkInfo.receive == '1' ? udid : talkInfo.udid),
        "name2": (talkInfo.receive == '1' ? name : toName),
        "time1": talkInfo.start,
        "time2": endTime
      }
    };
console.log(options);
    //リクエスト送信
    request(options, function (error, response, body) {
console.log(error, body);
      //コールバックで色々な処理
      //console.log(body);
    })
  },

  doTalkEnd: function(udid, toClient) {
    var talkInfo = toClient.getTalkTo(udid);
    if (talkInfo) {
      this.postTalkLog(toClient.udid, talkInfo);
    }

    toClient.socket.emit("app", {message: "talk_end", udid: udid});
    //console.log('doTalkEnd ' + udid + '->' + toClient.udid);
    toClient.delTalkTo(udid);
    console.log(toClient.talkTo);
    if (toClient.talkTo.length > 0) {
      toClient.status = def.ECLIENT_STATUS.CLIENT_STATUS_TALK;
    } else if (toClient.hasHoldTo()) {
      toClient.status = def.ECLIENT_STATUS.CLIENT_STATUS_HOLD;
    } else {
      toClient.status = def.ECLIENT_STATUS.CLIENT_STATUS_STAND;
    }
    // app.groupcast(toClient.code, 'status_change', {"MYID" : toClient.udid, "STATUS": toClient.status.toString()});
    toClient.socket.broadcast.emit('app', {message: "status_change", info: {"MYID" : toClient.udid, "STATUS": toClient.status.toString()}});
  },

  login: function(socket, data) {
    console.log("login:", data);
    var logined = app.getClient(data.MYID);
    if (logined) {
      socket.emit('app', {message: 'from_server', productName: '%logined'});
      return;
    }
    var client = app.addClient(socket, data);
    socket.emit('app', {message: 'from_server', productName: app.productName, sockID: socket.id});
    socket.join(data.DELEGATOR);
    socket.join(data.GROUP);
    if (typeof data.CODES !== 'undefined') {
      for (var i = 0; i < data.CODES.length; i++) {
        if (data.DELEGATOR === data.CODES[i]) {
          continue;
        }
        socket.join(data.CODES[i]);
        socket.join(data.CODES[i] + '_STAFF');
      }
    }

    // app.groupcast(data.DELEGATOR, "app", {message: 'login', info: {client: client.toStatusDic(), sockID: client.socket.id}});
    socket.broadcast.emit('app', {message: 'login', info: {client: client.toStatusDic(), sockID: client.socket.id}});
  },

  logout: function(socket) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }
    var udid = client.udid;
    console.log("logout:", udid);
    app.delClient(client);
    app.groupcast(client.code, 'status_change', {"MYID" : udid, "STATUS": def.ECLIENT_STATUS.CLIENT_STATUS_NOT_CONNECT.toString()});
    app.groupcast(client.code, 'app', {message: "status_change", info: {"MYID" : udid, "STATUS": def.ECLIENT_STATUS.CLIENT_STATUS_NOT_CONNECT.toString()}});
    //delete app.clients[socket.id];
    //delete app.groupCalling[udid];
  },

  clientInfo: function(socket, to) {
    var toClient = app.getClient(to);
    if (toClient) {
      socket.emit("app", {message: 'client_info', info: {client: toClient.toStatusDic(), sockID: toClient.socket.id}});
    }
  },

  clientsStatus: function(socket, data) {
    //console.log("clientsStatus:", data);
    var client;
    var group = data;
    jsonObj = {};
    for (var id in app.clients) {
      if (id == socket.id) {
        continue;
      }
      client = app.clients[id];
      if (client.socket.connected) {
        jsonObj[client.udid] = client.toStatusDic();
      } else {
        jsonObj[client.udid] = {"status": def.ECLIENT_STATUS.CLIENT_STATUS_NOT_CONNECT.toString(), "udid": client.udid};
        this.doDisconnect(id);
      }
    }

    app.addressList.forEach(function(val, index) {
      if (group.length == 0 || val["BOOK_GRP"] == group) {
        client = app.getClient(val["TARGET_ID"]);
        if (client != null) {
          if (!client.socket.connected) {

          }
          jsonObj[client.udid] = client.toStatusDic();
        } else {
          jsonObj[val["TARGET_ID"]] = {"status": def.ECLIENT_STATUS.CLIENT_STATUS_NOT_CONNECT.toString(), "udid": val["TARGET_ID"]};
        }
      }
    });
    socket.emit("app", {message: 'clients_status', data: jsonObj});
  },

  calledCheck: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }
    var to = data.toString();
    var codeMstId = to.split('_');
    var group = codeMstId[0] + '_STAFF';
    console.log('called check [' + to + '] to group[' + group + ']');
    app.groupcast(group, 'app', {message: 'called_check', "MYID" : client.udid, "TO": to});
  },

  callRequest: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }
    var to = data.toString();
    // console.log('call request ' + client.udid + ' -> ' + to);

    var toClient;
    var date = new Date();
    var now = date.getFullYear() + '/' + ('0' + (date.getMonth() + 1)).slice(-2) + '/' + ('0' + date.getDate()).slice(-2) + ' ' + ('0' + date.getHours()).slice(-2) + ':' + ('0' + date.getMinutes()).slice(-2);

    if (to.substring(0, 1) == '@') {
      // グループ呼び出し
      var toGroup = to.substring(1);

      app.groupcast(toGroup, "app", {message: "call", info: {udid: client.udid, sockID: client.socket.id}});
      for (var id in app.clients) {
        if (id == socket.id) {
          continue;
        }
        toClient = app.clients[id];
        if (toClient.group == toGroup) {
          client.callTo.push(toClient.udid);
        } else {
          try {
            if (app.pushmap[toClient.udid].codes.indexOf(toGroup) !== -1) {
              client.callTo.push(toClient.udid);
              console.log(toClient.udid + ' add to callTo');
            }
          } catch (e) {
            console.log(e);
          }
        }
      }
      client.callToGroup = toGroup;
      client.status = def.ECLIENT_STATUS.CLIENT_STATUS_CALL;
      app.groupCalling[client.udid] = toGroup;
      console.log(toGroup + ' <= push');
      app.pushToGroup(toGroup, "緊急呼び出し [" + client.udid + "]" + (client.name ? client.name + '' : '') + " " + now);
      return;
    }

    var callOK = 0;
    toClient = app.getClient(to);

    if (toClient == null) {
      callOK = 1;
      client.status = def.ECLIENT_STATUS.CLIENT_STATUS_CALL;
      client.callTo.push(to);
      app.pushToUdid(to, "呼び出し [" + client.udid + "]" + (client.name.length ? client.name + '' : '') + " " + now);
      // app.pushToUdid(to, "【" + client.udid + "】" + (client.name.length ? client.name + 'さんから' : '') + "呼び出し");
    } else if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_CALL) {
      callOK = 2;
    } else if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_TALK) {
      callOK = 3;
      // client.status = def.ECLIENT_STATUS.CLIENT_STATUS_CALL;
      // client.socket.broadcast.emit('status_change', {"MYID" : client.udid, "STATUS": client.status.toString()});
      // client.socket.broadcast.emit('app', {message: "status_change", info: {"MYID" : client.udid, "STATUS": client.status.toString()}});
      // toClient.socket.emit("app", {message: "call", info: {udid: client.udid, sockID: client.socket.id}});
      // client.callTo.push(toClient.udid);
    } else if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_MULTI) {
      callOK = 3;
    } else if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_HOLD) {
      callOK = 3;
    } else if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_HOLDED) {
      callOK = 3;
    } else if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_STAND) {
      client.status = def.ECLIENT_STATUS.CLIENT_STATUS_CALL;
      app.groupcast(client.code, 'status_change', {"MYID" : client.udid, "STATUS": client.status.toString()});
      app.groupcast(client.code, 'app', {message: "status_change", info: {"MYID" : client.udid, "STATUS": client.status.toString()}});
      toClient.socket.emit("app", {message: "call", info: {udid: client.udid, sockID: client.socket.id}});
      client.callTo.push(toClient.udid);
      app.pushToUdid(to, "呼び出し [" + client.udid + "]" + (client.name.length ? client.name + '' : '') + " " + now);
    }

    if (callOK > 0) {
      socket.emit("app", {message: 'not_connect', info: callOK.toString()});
    }
  },

  pcCallRequest: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    var to = data;
    var toClient = app.getClient(to);
    var isEnd = false;
    if (toClient == null) {
      isEnd = true;
    } else {
      if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_CALL) {
        if (!toClient.isCallTo(client.udid)) {
          console.log('call accept not callto ' +  client.udid, toClient.callTo);
          isEnd = true;
        } else {
          console.log('call accept ' +  client.udid + ' -> ' + toClient.udid + ':isEnd', isEnd);
        }
      } else {
        console.log('call accept not status_call ' +  client.udid, toClient.callTo);
        isEnd = true;
      }
    }

    if (isEnd) {
      // 応答状態オフ
      socket.emit("accept_error", to);
      // clients.setClient(socket.udid, {status: lp.ECLIENT_STATUS.CLIENT_STATUS_STAND});
    } else {
      toClient.socket.emit("app", {message: "call", info: {udid: client.udid, sockID: client.socket.id}});
    }

  },

  callCancel: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }
    // 発信元コール状態オフ
    if (client.hasHoldTo()) {
      client.status = def.ECLIENT_STATUS.CLIENT_STATUS_HOLD;
    } else {
      client.status = def.ECLIENT_STATUS.CLIENT_STATUS_STAND;
    }

    var to = data.toString();
    console.log("call cancel " + client.udid + " -> " + to);

    var toClient;
    if (to.substring(0, 1) == '@') {
      for (var i = 0; i < client.callTo.length; i++) {
        var toID = client.callTo[i];
        toClient = app.getClient(toID);
        if (toClient != null) {
          toClient.socket.emit("app", {message: "call_cancel", udid: client.udid});
        }
      }
    } else {
      toClient = app.getClient(to);
      if (toClient != null) {
        toClient.socket.emit("app", {message: "call_cancel", udid: client.udid});
      }
    }
    client.callToGroup = "";
    client.callTo = [];
    delete app.groupCalling[client.udid];
  },

  callReject: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    var to = data;
    console.log("call reject " + client.udid + " -> " + to);

    var toClient = app.getClient(to);
    if (toClient == null) {
      return;
    }

    // 発信元呼び出し先削除
    toClient.delCallTo(client.udid);

    // 発信元コール状態オフ
    if (toClient.callTo.length == 0) {
      if (!toClient.hasHoldTo()) {
        toClient.status = def.ECLIENT_STATUS.CLIENT_STATUS_STAND;
      } else {
        toClient.status = def.ECLIENT_STATUS.CLIENT_STATUS_HOLD;
      }
    }

    toClient.socket.emit('app', {message: 'call_reject', udid: client.udid});
  },

  callNotAuth: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    var to = data;
    console.log("call not auth " + client.udid + " -> " + to);

    var toClient = app.getClient(to);
    if (toClient == null) {
      return;
    }

    // 発信元呼び出し先削除
    toClient.delCallTo(client.udid);

    // 発信元コール状態オフ
    if (toClient.callTo.length == 0) {
      if (!toClient.hasHoldTo()) {
        toClient.status = def.ECLIENT_STATUS.CLIENT_STATUS_STAND;
      } else {
        toClient.status = def.ECLIENT_STATUS.CLIENT_STATUS_HOLD;
      }
    }

    toClient.socket.emit('app', {message: 'call_not_auth', udid: client.udid});
  },

  callAccept: function(socket, data) {
    var client = app.clients[socket.id];
    var startTime = utils.dateFormat(new Date(), 'yyyy-mm-dd H:i:s');
    if (typeof client === 'undefined') {
      return;
    }

    var to = data;
    var toClient = app.getClient(to);
    var isEnd = false;
    if (toClient == null) {
      isEnd = true;
    } else {
      if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_CALL) {
        if (!toClient.isCallTo(client.udid)) {
          console.log('call accept not callto ' +  client.udid, toClient.callTo);
          isEnd = true;
        } else {
          console.log('call accept ' +  client.udid + ' -> ' + toClient.udid + ':isEnd', isEnd);
        }
      } else {
        console.log('call accept not status_call ' +  client.udid, toClient.callTo);
        isEnd = true;
      }
    }

    if (isEnd) {
      // 応答状態オフ
      socket.emit("accept_error", to);
      // clients.setClient(socket.udid, {status: lp.ECLIENT_STATUS.CLIENT_STATUS_STAND});
    } else {
      toClient.socket.emit("app", {message: "call_accept", udid: client.udid});

      // 発信元呼び出し先クリア
      if (toClient.callToGroup.length > 0) {
        toClient.callToGroup = "";
        delete app.groupCalling[toClient.udid];
      }
      toClient.callTo = [];

      // 通話状態
      client.talkTo.push({udid: toClient.udid, start: startTime, receive: '1'});
      client.status = def.ECLIENT_STATUS.CLIENT_STATUS_TALK;
      app.groupcast(client.code, 'status_change', {"MYID" : client.udid, "STATUS": client.status.toString()});
      app.groupcast(client.code, 'app', {message: "status_change", info: {"MYID" : client.udid, "STATUS": client.status.toString()}});

      toClient.talkTo.push({udid: client.udid, start: startTime, receive: '0'});
      toClient.status = def.ECLIENT_STATUS.CLIENT_STATUS_TALK;
      app.groupcast(client.code, 'status_change', {"MYID" : toClient.udid, "STATUS": toClient.status.toString()});
      app.groupcast(client.code, 'app', {message: "status_change", info: {"MYID" : toClient.udid, "STATUS": toClient.status.toString()}});
    }
  },

  isCallRequest: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }
    var to = data.toString();
    console.log('call request ? ' + client.udid + ' -> ' + to);

    var toClient = app.getClient(to);
    if (toClient && toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_CALL) {
      if (app.groupCalling[to] == client.group) {
        client.socket.emit("app", {message: "call", info: {udid: toClient.udid, sockID: toClient.socket.id}});
        toClient.callTo.push(client.udid);
        return;
      } else {
        client.socket.emit("app", {message: "call", info: {udid: toClient.udid, sockID: toClient.socket.id}});
        return;
      }
    }

    client.socket.emit("app", {message: "call_cancel", udid: to});
  },

  talkEnd: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    console.log('talk end ', client.udid);

    var to = data;
    var toClient = app.getClient(to);
    if (toClient == null) {
      return;
    }

    client.delTalkTo(toClient.udid);
    if (client.talkTo.length > 0) {
      client.status = def.ECLIENT_STATUS.CLIENT_STATUS_TALK;
    } else if (client.hasHoldTo()) {
      client.status = def.ECLIENT_STATUS.CLIENT_STATUS_HOLD;
    } else {
      client.status = def.ECLIENT_STATUS.CLIENT_STATUS_STAND;
    }
    client.socket.broadcast.emit('status_change', {"MYID" : client.udid, "STATUS": client.status.toString()});
    client.socket.broadcast.emit('app', {message: "status_change", info: {"MYID" : client.udid, "STATUS": client.status.toString()}});

    this.doTalkEnd(client.udid, toClient);
  },

  hangup: function(socket, data) {
    var toClient
      , to;
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    //console.log('hangup ', client.udid, client.talkTo);

    for (var i = 0; i < client.talkTo.length; i++) {
      to = client.talkTo[i].udid;
      toClient = app.getClient(to);
      if (toClient) {
        //client.delTalkTo(toClient.udid);
        this.doTalkEnd(client.udid, toClient);
      }
    }
    client.talkTo = [];
    if (client.hasHoldTo()) {
      client.status = def.ECLIENT_STATUS.CLIENT_STATUS_HOLD;
    } else {
      client.status = def.ECLIENT_STATUS.CLIENT_STATUS_STAND;
    }

    // app.groupcast(client.code, 'status_change', {"MYID" : client.udid, "STATUS": client.status.toString()});
    // app.groupcast(client.code, 'app', {message: "status_change", info: {"MYID" : client.udid, "STATUS": client.status.toString()}});
    client.socket.broadcast.emit('app', {message: "status_change", info: {"MYID" : client.udid, "STATUS": client.status.toString()}});
  },

  callHold: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    var to = data;
    var toClient = app.getClient(to);
    var talkInfo;

    var isHold = false;
    if (toClient == null) {
      //console.log('call hold ' + to + ' is null');
    } else if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_TALK && toClient.isTalkTo(client.udid)) {
      toClient.socket.emit("app", {message: "hold", udid: client.udid});

      talkInfo = client.getTalkTo(toClient.udid);
      client.delTalkTo(toClient.udid);
      client.holdTo = talkInfo;
      client.status = def.ECLIENT_STATUS.CLIENT_STATUS_HOLD;

      talkInfo = toClient.getTalkTo(client.udid);
      toClient.delTalkTo(client.udid);
      toClient.holdFrom = talkInfo;
      toClient.status = def.ECLIENT_STATUS.CLIENT_STATUS_HOLDED;
      isHold = true;
    }

    console.log('hold ' +  client.udid + ' -> ' + to + ':isHold', isHold);

    if (!isHold) {
      socket.emit("app", {message: "talk_end", info: to});
      client.status = def.ECLIENT_STATUS.CLIENT_STATUS_STAND;
      app.groupcast(client.code, 'status_change', {"MYID" : client.udid, "STATUS": client.status.toString()});
      app.groupcast(client.code, 'app', {message: "status_change", info: {"MYID" : client.udid, "STATUS": client.status.toString()}});
    }
  },

  callHoldClear: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    var to = data;
    var toClient = app.getClient(to);
    var talkInfo;

    var isClear = false;
    if (toClient == null) {
    } else {
      talkInfo = client.holdTo;//client.getTalkTo(toClient.udid);
      if (talkInfo) {
        if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_HOLDED && toClient.isHolded(client.udid)) {
          toClient.socket.emit("app", {message: "hold_clear", info: {udid: client.udid, sockID: client.socket.id}});

          toClient.status = def.ECLIENT_STATUS.CLIENT_STATUS_TALK;
          toClient.talkTo.push(toClient.holdFrom);
          toClient.holdFrom = {};

          client.talkTo.push(talkInfo);
          client.status = def.ECLIENT_STATUS.CLIENT_STATUS_TALK;
          isClear = true;
        }
      }
    }

    console.log('hold clear ' +  client.udid + ' -> ' + to + ':isClear', isClear);

    if (!isClear) {
      socket.emit("app", {message: "talk_end", info: toClient.udid});
      client.status = def.ECLIENT_STATUS.CLIENT_STATUS_STAND;
      app.groupcast(client.code, 'status_change', {"MYID" : client.udid, "STATUS": client.status.toString()});
      app.groupcast(client.code, 'app', {message: "status_change", info: {"MYID" : client.udid, "STATUS": client.status.toString()}});
    }

    client.holdTo = {};
  },

  holdEnd: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    this.postTalkLog(client.udid, client.holdTo);

    client.holdTo = {};
    client.status = def.ECLIENT_STATUS.CLIENT_STATUS_STAND;
    app.groupcast(client.code, 'status_change', {"MYID": client.udid, "STATUS": client.status.toString()});
    app.groupcast(client.code, 'app', {message: "status_change", info: {"MYID" : client.udid, "STATUS": client.status.toString()}});

    var to = data;
    var toClient = app.getClient(to);

    if (toClient == null) {
      return;
    }

    this.doHoldEnd(client, toClient);
  },

  doHoldEnd: function(client, toClient) {

    console.log('hold end ' +  client.udid + ' -> ' + toClient.udid);

    toClient.socket.emit("app", {message: "talk_end", udid: client.udid});

    toClient.holdFrom = {};
    toClient.status = def.ECLIENT_STATUS.CLIENT_STATUS_STAND;
    app.groupcast(client.code, 'status_change', {"MYID" : toClient.udid, "STATUS": toClient.status.toString()});
    app.groupcast(client.code, 'app', {message: "status_change", info: {"MYID" : toClient.udid, "STATUS": toClient.status.toString()}});
  },

  holdedEnd: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    this.postTalkLog(client.udid, client.holdFrom);

    client.holdFrom = {};
    client.status = def.ECLIENT_STATUS.CLIENT_STATUS_STAND;
    app.groupcast(client.code, 'status_change', {"MYID": client.udid, "STATUS": client.status.toString()});
    app.groupcast(client.code, 'app', {message: "status_change", info: {"MYID" : client.udid, "STATUS": client.status.toString()}});


    var to = data;
    var toClient = app.getClient(to);

    if (toClient == null) {
      return;
    }

    this.doHoldedEnd(client, toClient);
  },

  doHoldedEnd: function(client, toClient) {
    console.log('holded end ' +  client.udid + ' -> ' + toClient.udid);

    toClient.socket.emit("app", {message: "talk_end", udid: client.udid});

    toClient.holdTo = {};
    if (toClient.talkTo.length > 0) {
      toClient.status = def.ECLIENT_STATUS.CLIENT_STATUS_TALK;
    } else {
      toClient.status = def.ECLIENT_STATUS.CLIENT_STATUS_STAND;
    }
    app.groupcast(client.code, 'status_change', {"MYID" : toClient.udid, "STATUS": toClient.status.toString()});
    app.groupcast(client.code, 'app', {message: "status_change", info: {"MYID" : toClient.udid, "STATUS": toClient.status.toString()}});
  },

  callThreeway: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }
    var startTime = utils.dateFormat(new Date(), 'yyyy-mm-dd H:i:s');

    if (typeof data.talkID1 === 'undefined' || typeof data.talkID2 === 'undefined' || typeof data.roomId === 'undefined') {
      client.socket.emit("app", {message: "threeway_call_error", err: "parameter error"});
      return;
    }

    if (client.talkTo.length != 1) {
      client.socket.emit("app", {message: "threeway_call_error", err: "status error"});
      return;
    }

    if (!client.hasHoldTo()) {
      client.socket.emit("app", {message: "threeway_call_error", err: "status error"});
      return;
    }

    var talkInfo = client.talkTo[0];
    var talkID = talkInfo.udid;

    var holdInfo = client.holdTo;
    var holdID = holdInfo.udid;
    if (talkID != data.talkID1 || holdID != data.talkID2) {
      client.socket.emit("app", {message: "threeway_call_error", err: "id is not match"});
      return;
    }
    var talkClient = app.getClient(talkID);
    if (talkClient == null) {
      client.socket.emit("app", {message: "threeway_call_error", err: "talk client error"});
      return;
    }

    var holdClient = app.getClient(holdID);
    if (holdClient == null) {
      client.socket.emit("app", {message: "threeway_call_error", err: "hold client error"});
      return;
    }

    var roomID = data.roomId;
    console.log('call threeway(' + roomID + ') ' +  client.udid + ' -> ' + talkID + ':' + holdID);
    console.log(talkInfo);
    console.log(holdInfo);
    client.talkTo.push(holdInfo);
    client.holdTo = {};
    client.status = def.ECLIENT_STATUS.CLIENT_STATUS_MULTI;
    client.socket.emit("app", {message: "threeway_response", info: {"roomID": roomID, "talkID1": talkID, sockID1: talkClient.socket.id, "talkID2": holdID, sockID2: holdClient.socket.id}});

    talkClient.socket.emit("app", {message: "threeway", info: {"roomID": roomID, "talkID1": client.udid, sockID1: client.socket.id, "talkID2": holdID, sockID2: holdClient.socket.id}});
    talkClient.talkTo.push({udid: holdID, start: startTime, receive: '0'});
    talkClient.status = def.ECLIENT_STATUS.CLIENT_STATUS_MULTI;

    holdClient.socket.emit("app", {message: "threeway", info: {"roomID": roomID, "talkID1": client.udid, sockID1: client.socket.id, "talkID2": talkID, sockID2: talkClient.socket.id}});
    holdClient.talkTo.push(holdClient.holdFrom);
    holdClient.talkTo.push({udid: talkID, start: startTime, receive: '1'});
    holdClient.holdFrom = {};
    holdClient.status = def.ECLIENT_STATUS.CLIENT_STATUS_MULTI;
    holdClient.socket.broadcast.emit('status_change', {"MYID" : holdClient.udid, "STATUS": holdClient.status.toString()});
    holdClient.socket.broadcast.emit('app', {message: "status_change", info: {"MYID" : holdClient.udid, "STATUS": holdClient.status.toString()}});
  },

  toThreeway: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }
    var to = data.to;
    var idx = data.idx;
    console.log('toThreeway request [' + idx + ']' + client.udid + ' -> ' + to);

    var toClient = app.getClient(to);

    if (toClient != null) {
      toClient.socket.emit("app", {message: "to_threeway", info: {udid: client.udid, sockID: client.socket.id, idx: idx}});
    }
  },

  requestRecord: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }
    var to = data.to;
    var recId = data.recid;
    console.log('record request [' + recId + ']' + client.udid + ' -> ' + to);

    var toClient = app.getClient(to);

    if (toClient == null) {
    } else if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_TALK && toClient.isTalkTo(client.udid)) {
      toClient.socket.emit("app", {message: "request_record", info: {udid: client.udid, sockID: client.socket.id, recid: recId}});
      return;
    }
    client.socket.emit("app", {message: "request_record_error", err: "client is not connected"});
  },

  requestRecordReject: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }
    var to = data.toString();
    var toClient = app.getClient(to);
    if (toClient != null) {
      toClient.socket.emit("app", {message: "request_record_reject", info: {udid: client.udid, sockID: client.socket.id}});
    }
  },

  requestRecordAccept: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }
    var to = data.to;
    var recId = data.recid;
    console.log('record request [' + recId + ']' + client.udid + ' -> ' + to);

    var toClient = app.getClient(to);

    if (toClient == null) {
    } else if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_TALK && toClient.isTalkTo(client.udid)) {
      var startTime = utils.dateFormat(new Date(), 'yyyy-mm-dd H:i:s');
      toClient.socket.emit("app", {message: "request_record_accept", info: {udid: client.udid, sockID: client.socket.id, recid: recId}});
      toClient.record = {udid: client.udid, start: startTime, receive: '0', recid: recId};
      return;
    }

    client.socket.emit("app", {message: "request_record_accept_error", err: "client is not connected"});
  },

  recordStop: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }
    var to = data.to;
    var recId = data.recid;
    console.log('record stop [' + recId + ']' + client.udid + ' -> ' + to);

    var toClient = app.getClient(to);

    if (toClient == null) {
      return;
    } else if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_TALK && toClient.isTalkTo(client.udid)) {
      toClient.socket.emit("app", {message: "record_stop", info: {udid: client.udid, sockID: client.socket.id, recid: recId}});
    }

    this.postRecordLog(client.udid, client.record);
    client.record = {};
    this.postRecordLog(toClient.udid, toClient.record);
    toClient.record = {};
  },

  postRecordLog: function(udid, recordInfo) {
    console.log('postRecordLog', udid, recordInfo);
    if (!recordInfo.udid) {
      return;
    }
    var endTime = utils.dateFormat(new Date(), 'yyyy-mm-dd H:i:s');
    var options = {
      url: def.MCS_DOMAIN + "delegator/add_record_log.php",
      method: 'POST',
      headers: {
        "Content-type": "application/json"
      },
      json: true,
      form: {
        "cd": app.delegatorCode,
        "recid": recordInfo.recid,
        "udid1": (recordInfo.receive == '1' ? recordInfo.udid : udid),
        "name1": (recordInfo.receive == '1' ? app.getAddressIDName(recordInfo.udid) : app.getAddressIDName(udid)),
        "udid2": (recordInfo.receive == '1' ? udid : recordInfo.udid),
        "name2": (recordInfo.receive == '1' ? app.getAddressIDName(udid) : app.getAddressIDName(recordInfo.udid)),
        "time1": recordInfo.start,
        "time2": endTime
      }
    };

    //リクエスト送信
    request(options, function (error, response, body) {
      //コールバックで色々な処理
      //console.log(body);
    })
  },

  requestPhoto: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    var to = data.udid;
    var toClient = app.getClient(to);

    var isSend = false;
    if (toClient == null) {
    } else if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_TALK && toClient.isTalkTo(client.udid)) {
      toClient.socket.emit("app", {message: "request_photo", info: {udid: client.udid, type: data.type, dispSize: client.dispSize}});
      isSend = true;
    }

    if (!isSend) {
      socket.emit("app", {message: "photo_request_error", udid: to});
    }
  },

  photoImage: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    if (client.talkTo.length != 1) {
      return;
    }

    var talkInfo = client.talkTo[0];
    var to = talkInfo.udid;
    var toClient = app.getClient(to);

    console.log('photoImage ' +  client.udid + ' -> ' + to);

    if (toClient) {
      toClient.socket.emit("app", {message: "photo_image", info: {udid: client.udid, data: data, dispSize: client.dispSize}});
    }
  },

  safetyCheck: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    var to = data.toString();
    var toClient = app.getClient(to);

    console.log('safety check ' + client.udid + ' -> ' + to);

    var isSend = false;
    if (toClient == null) {
    } else if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_STAND) {
      toClient.socket.emit("app", {message: "safety_check", udid: client.udid});
      toClient.safetyCheck.push(client.udid);
      isSend = true;
    }

    if (!isSend) {
      socket.emit("app", {message: "safety_check_error", udid: to});
    }
  },

  safetyCheckStart: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    console.log('safety check start :' + client.udid);

    var toClient;
    for (var i = 0; i < client.safetyCheck.length; i++) {
      toClient = app.getClient(client.safetyCheck[i]);
      if (toClient) {
        toClient.socket.emit("app", {message: "safety_check_start", udid: client.udid, sockID: client.socket.id});
      }
    }
  },

  safetyCheckError: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    console.log('safety check error :' + client.udid);

    var toClient;
    for (var i = 0; i < client.safetyCheck.length; i++) {
      toClient = app.getClient(client.safetyCheck[i]);
      if (toClient) {
        toClient.socket.emit("app", {message: "safety_check_error", udid: client.udid, sockID: client.socket.id});
      }
    }
    client.safetyCheck = [];
  },

  safetyCheckStop: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    console.log('safety check stop :' + client.udid);

    var toClient;
    for (var i = 0; i < client.safetyCheck.length; i++) {
      toClient = app.getClient(client.safetyCheck[i]);
      if (toClient) {
        toClient.socket.emit("app", {message: "safety_check_stop", udid: client.udid});
      }
    }
    client.safetyCheck = [];
  },

  safetyCheckEnd: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    var to = data;
    var toClient = app.getClient(to);

    console.log('safety check end' + client.udid + ' -> ' + to);

    if (toClient) {
      toClient.delSafetyCheck(client.udid);
      if (toClient.safetyCheck.length == 0) {
        toClient.socket.emit("app", {message: "safety_check_end", udid: client.udid});
      }
    }
  },

  liveCheck: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    var to = data.toString();
    var toClient = app.getClient(to);

    console.log('live check ' + client.udid + ' -> ' + to);

    var isSend = false;
    if (toClient == null) {
    } else if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_LIVE) {
      toClient.socket.emit("app", {message: "live_check", udid: client.udid});
      isSend = true;
    }

    if (!isSend) {
      socket.emit("app", {message: "live_check_error", udid: to});
    }
  },

  liveCheckError: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    console.log('live check error :' + client.udid);

    var to = data.toString();
    var toClient = app.getClient(to);
    if (toClient) {
      toClient.socket.emit("app", {message: "live_check_error", udid: client.udid, sockID: client.socket.id});
    }
  },

  liveCheckEnd: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    var to = data;
    var toClient = app.getClient(to);

    console.log('live check end' + client.udid + ' -> ' + to);

    if (toClient) {
      toClient.socket.emit("app", {message: "live_check_end", udid: client.udid});
    }
  },


  draw: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    var to = data.toID;
    var toClient = app.getClient(to);

    if (toClient) {
      toClient.socket.emit("app", {message: "draw", info: data});
    }
  },

  talk: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    var toClient;
    for (var i = 0; i < client.talkTo.length; i++) {
      toClient = app.getClient(client.talkTo[i].udid);
      if (toClient != null) {
        toClient.socket.emit('app', {message: "talk", info: data});
      }
    }
  },

  viewcanImage: function(socket, data) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    var toClient;
    if (client.status == def.ECLIENT_STATUS.CLIENT_STATUS_LIVE) {
      for (id in app.clients) {
        toClient = app.clients[id];
        if (toClient == null) {
          continue;
        }
        if (toClient.code != client.code) {
          continue;
        }
        if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_STAND || toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_HOLD) {
          toClient.socket.emit("app", {message: "viewcan_image", info: {udid: client.udid, data: data.toString()}});
        }
      }
    }
  },

  emitToTalkTo: function(socket, event) {
    var client = app.clients[socket.id];
    if (typeof client === 'undefined') {
      return;
    }

    for (var i = 0; i < client.talkTo.length; i++) {
      var toClient = app.getClient(client.talkTo[i].udid);
      if (toClient != null) {
        toClient.socket.emit('app', {message: event, udid: client.udid});
      }
    }
  }


};




module.exports = tcp;

