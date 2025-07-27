var utils = require('../utils.js');
var app = require('../app.js');
var def = require('../define.js');
var express = require('express');
var request = require('request');
var router = express.Router();

router.get('/', function (req, res, next) {
  res.redirect('/admin');
});

router.get('/ping', function (req, res, next) {
  res.json({"STATUS": "OK"});
});

router.get('/clinicid', function (req, res, next) {
  res.json({"STATUS": "OK"});
});

router.get('/address_json', function (req, res, next) {
  res.header("Access-Control-Allow-Origin", "*");
  res.header("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept");

  var group = req.query.group === undefined ? '' : req.query.group;
  var retAddress = [];
  app.addressList.forEach(function(val, index) {
    if (group.length == 0 || val["BOOK_GRP"] == group) {
      retAddress.push(val);
    }
  });
  jsonObj = {"ADDRESS": retAddress};
  res.json(jsonObj);
});

router.get('/status_json', function (req, res, next) {
  res.json({"STATUS": "OK"});
});

router.get('/clients_info', function (req, res, next) {
  var jsonObj = {};
  for (var key in app.clients) {
    var client = app.clients[key];
    jsonObj[client.udid] = {
      status: client.status,
      // tcpIP: client.tcpIP,
      // tcpPort: client.tcpPort,
      group: client.group,
      dispSize: client.dispSize,
      marker: client.marker,
      udpIP: client.udpIP,
      udpPort: client.udpPort,
      safetyCheck: client.safetyCheck,
      callToGroup: client.callToGroup,
      callTo: client.callTo,
      talkTo: client.talkTo,
      holdTo: client.holdTo,
      holdFrom: client.holdFrom,
      firToken: client.firToken
    };
  }
  res.json(jsonObj);
});

router.get('/callbutton_info', function (req, res, next) {
  if (!req.session.user) {
    res.json({"STATUS": "NG"});
    return;
  }
  app.callButtonModel.find({}, null, {sort: {'_id': 1}}, function(err , datas) {
    if (err) {
      res.json({"STATUS": "NG"});
    }
    var list = [];
    for (i = 0, size = datas.length; i < size; i++) {
      list.push(datas[i]);
    }
    res.json({"STATUS": "OK", "LIST": list});
  });
});

router.post('/save_callbutton', function (req, res, next) {
  if (!req.session.user) {
    res.json({"STATUS": "NOLOGIN"});
    return;
  }
  if (req.body["BUTTON_ID"].length  == 0 || req.body["BOOK_GRP"].length == 0 || req.body["TARGET_ID"].length == 0 || req.body["NAME"].length == 0) {
    var err = '入力が正しくありません。確認して再入力してください。';
    res.json({"STATUS": "NG", "MSG": err});
    return;
  }
  app.callButtonModel.find({"BUTTON_ID": req.body["BUTTON_ID"]}, function(err , datas) {
    if (err) {
      res.json({"STATUS": "NG", "MSG": "データベースエラー"});
    }
    if (datas.length > 0) {
      var save = {
        "BOOK_GRP": req.body["BOOK_GRP"],
        "TARGET_ID": req.body["TARGET_ID"],
        "NAME": req.body["NAME"]
      };
      app.callButtonModel.update({"BUTTON_ID": req.body["BUTTON_ID"]}, {$set: save}, function(err) {
        if (err) {
          res.json({"STATUS": "NG", "MSG": "データベースエラー"});
        }
        res.json({"STATUS": "OK"});
      });
      return;
    }

    var callbuttonData = new app.callButtonModel();
    callbuttonData["BOOK_GRP"] = req.body["BOOK_GRP"];
    callbuttonData["TARGET_ID"] = req.body["TARGET_ID"];
    callbuttonData["BUTTON_ID"] = req.body["BUTTON_ID"];
    callbuttonData["NAME"] = req.body["NAME"];
    callbuttonData.save(function(err) {
      if (err) {
        res.json({"STATUS": "NG", "MSG": "データベースエラー"});
      }
      res.json({"STATUS": "OK"});
    });
  });
});

router.post('/del_callbutton', function (req, res, next) {
  if (!req.session.user) {
    res.json({"STATUS": "NOLOGIN"});
    return;
  }
  app.callButtonModel.findByIdAndRemove(req.body.ID, function(err , data) {
    if (err) {
      res.json({"STATUS": "NG", "MSG": "データベースエラー"});
    }
    res.json({"STATUS": "OK"});
  });
});

router.get('/push_info', function (req, res, next) {
//  if (!req.session.user) {
//    res.json({"STATUS": "NG"});
//    return;
//  }
  var item;
  var list = [];
  Object.keys(app.pushmap).forEach(function(udid) {
    item = app.pushmap[udid];
    item.udid = udid;
    list.push(item);
  });
  res.json({"STATUS": "OK", "LIST": list});
});

router.post('/push_test', function (req, res, next) {
  if (!req.session.user) {
    res.json({"STATUS": "NOLOGIN"});
    return;
  }
  app.pushTest(req.body.TOKEN, req.body.TITLE, req.body.MESSAGE);
  res.json({"STATUS": "OK"});
});

router.get('/push_test2', function (req, res, next) {
  if (!req.session.user) {
    res.json({"STATUS": "NOLOGIN"});
    return;
  }
  app.pushToGroup(req.body.GROUP, "【" + req.body.TID + "】緊急呼び出し");
  res.json({"STATUS": "OK"});
});

router.get('/push_receive', function (req, res, next) {
  var tid = req.query.TID;
  var toGroup = req.query.GID;

  if (tid.length == 0 || toGroup.length == 0) {
    res.json({"STATUS": "NG"});
  } else {
    var client = app.getClient(tid);
    if (client) {

      if (client.status != def.ECLIENT_STATUS.CLIENT_STATUS_STAND) {
        res.json({"STATS": "0"});
        return;
      }

//console.log(client);
//res.json({"STATUS": "1"});
//return;

      //client.socket.emit('call_button', {});
      client.socket.emit("app", {message: 'call_button'});

      var toClient;

      app.groupcast(toGroup, "app", {message: "call", info: {udid: client.udid, sockID: client.socket.id}});
      //app.groupcast(toGroup, "call", client.udid);
//console.log(app.clients);
      for (var key in app.clients) {
//console.log(key);
        if (key == client.socket.id) {
          continue;
        }
        toClient = app.clients[key];
        if (toClient.group == toGroup) {
          client.callTo.push(toClient.udid);
        }
      }
      client.callToGroup = toGroup;
      client.status = def.ECLIENT_STATUS.CLIENT_STATUS_CALL;
      app.groupCalling[client.udid] = toGroup;

      app.pushToGroup(toGroup, "【" + client.udid + "】" + (client.name.length ? client.name + 'さんから' : '') + "緊急呼び出し");
    } else {
      app.pushToGroup(toGroup, "【" + tid + "】緊急呼び出し");
    }

    process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
    var endTime = utils.dateFormat(new Date(), 'yyyy-mm-dd H:i:s');
    var options = {
      url: def.AMI_DOMAIN + "delegator/add_call_log",
      method: 'POST',
      headers: {
        "Content-type": "application/json"
      },
      json: true,
      form: {
        "token": app.amiToken,
        "id": app.masterId,
        "udid1": tid,
        "name1": client ? client.name : '',
        "udid2": toGroup,
        "time1": endTime,
        "time2": endTime
      }
    };

    //リクエスト送信
    request(options, function (error, response, body) {
console.log(error, body);
      //コールバックで色々な処理
      //console.log(body);
    });

    res.json({"STATUS": "OK"});
  }
});

module.exports = router;
