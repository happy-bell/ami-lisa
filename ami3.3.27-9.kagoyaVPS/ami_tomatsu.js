var path = require('path');
var scriptName = path.basename(__filename);
var scriptDir = __filename.substr(0, __filename.length - scriptName.length);
console.log(scriptName, scriptDir);
var appDir = scriptDir + 'apps/';

var app = require(appDir + 'app.js');
app.scriptName = scriptName;
app.scriptDir = scriptDir;

var fnHttp = require(appDir + 'http.js');
var tcp = require(appDir + 'tcp.js');
var def = require(appDir + 'define.js');
var http = require('http');
var https = require('https');
var request = require('request');
var server;
var config = require('config');
var mongoose = require('mongoose');
var request = require('request');
var fs = require('fs');
var db;
var ip = getLocalIP();
var ipTimer;

app.firebaseJsonPath = config.FIREBASE;
app.initializeFirebaseApp();

var sslOptions = {
  key: fs.readFileSync(config.SSLKEY),
  cert: fs.readFileSync(config.SSLCERT)
};

if (config.has('SSLCA')) {
  sslOptions['ca'] = fs.readFileSync(config.SSLCA);
  //console.log('read ca:' + sslOptions['ca']);
}

if (config["SSLUSE"]) {
  server = https.createServer(sslOptions, fnHttp);
} else {
  server = http.Server(fnHttp);
}

server.on('connection', function(sock) {

  sock.on('data', function(data) {
    //console.log(data.toString('utf8'));
    if (data.toString('utf8', 0, 3).trim() == 'ID:') {
      var msg = data.toString('utf8', 3, data.length - 3).trim().replace(/\s+/g, '');
      if (msg.length != 10) {
        var datamsg = data.toString('utf8',0,data.length).trim();
        datamsg = datamsg.replace(/ /g, '');
        msg = datamsg.substr(3);
        if (msg.length != 10) {
          return;
        }
      }
      var buttonID = msg.substr(0, 8);
      var keyNo = msg.substr(9, 1);
      console.log('button',buttonID,keyNo);

      if (keyNo == '1' || keyNo == '2' || keyNo == '3' || keyNo == '4') {
        app.callButtonModel.find({"BUTTON_ID": buttonID}, function(err , datas) {
          if (err) {
            return;
          }
          if (datas.length == 0) {
            var callbuttonData = new app.callButtonModel();
            callbuttonData["BOOK_GRP"] = 'xxxxxxx';
            callbuttonData["TARGET_ID"] = 'xxxxxxxx';
            callbuttonData["BUTTON_ID"] = buttonID;
            callbuttonData["NAME"] = '未設定';
            callbuttonData.save(function(err) {
              if (err) {
              }
            });
            return;
          }
          var callbutton = datas[0];
          //console.log(callbutton);

          if (callbutton["TARGET_ID"] == 'xxxxxxxx') {
            return;
          }

          var client = app.getClient(callbutton["TARGET_ID"]);
          var toGroup = callbutton["BOOK_GRP"];
          if (client) {

            if (client.status != def.ECLIENT_STATUS.CLIENT_STATUS_STAND) {
              return;
            }
            client.socket.emit('call_button', {});

            var toClient;

            app.groupcast(toGroup, "call", client.udid);
            for (var id in app.clients) {
              if (id == client.socket.id) {
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
          } else {
            console.log('client is not logined(push)');
            app.pushToGroup(toGroup, "【" + callbutton['TARGET_ID'] + "】緊急呼び出し");
          }
        });
      }
    }
  });

});


noClusterStart();
//clusterStart();

function noClusterStart() {
  if (!isConfig()) {
    process.exit();
  }

  app.masterId = config.MASTERID;
  app.delegatorCode = config.CODE;
  app.productName = config.PRODUCT;
  app.amiToken = config.AMI_TOKEN;
  console.log('MasterId:' + app.masterId + ' Product:' + app.productName + ' Code:' + app.delegatorCode);

// mongoDB
//  connectDatabase();
  start();
}

function connectDatabase() {
  db = mongoose.connect('mongodb://localhost/' + app.productName);

  mongoose.connection.on('error', function(err) {
    console.log('failed to connect a db : ' + err);
    process.exit();
  }).on('open', function() {
    start();
  });
}

function start() {
  //app.setDB(db);
  //app.loadAddressList();
  //app.mcs = config.Delegator.MCS;
  app.setGcmApiKey(config["GCM_API_KEY"]);

  server.listen(config.TCPPORT, function() {
    console.log('Server is running at ' + ip + ':' + config.TCPPORT);
    setProduct('1');
    ipTimer = setInterval(ipThread, 10 * 1000);
  });

  app.io = tcp.listen(server);
}

function isConfig() {
  if (!config.has('PRODUCT')) {
    console.log('failed to load config');
    return false;
  }

  return true;
}

function getLocalIP() {
  var os = require('os');
  var ifaces = os.networkInterfaces();
  var ret = '';

  Object.keys(ifaces).forEach(function (ifname) {
    if (ret.length > 0) {
      return;
    }
    var alias = 0;

    ifaces[ifname].forEach(function (iface) {
      if ('IPv4' !== iface.family || iface.internal !== false) {
        // skip over internal (i.e. 127.0.0.1) and non-ipv4 addresses
        return;
      }

      if (alias >= 1) {
        // this single interface has multiple ipv4 addresses
        // console.log(ifname + ':' + alias, iface.address);
      } else {
        // this interface has only one ipv4 adress
        // console.log(ifname, iface.address);
        ret = iface.address;
      }
      ++alias;
    });
  });
  return ret;
};

function ipThread() {
  setProduct('0');
}

function setProduct(startFlag) {
  var url = def.AMI_DOMAIN + "delegator/set?id=" + encodeURIComponent(app.masterId) + '&lip=' + ip + '&start=' + startFlag;
  var options = {
    url: url,
    method: 'GET',
  };

  //リクエスト送信
  request(options, function (error, response, body) {
    //コールバックで色々な処理
    //console.log(body);
  });
}

function setProductXX(startFlag) {
  var url = def.AMI_DOMAIN + "delegator/set?id=" + encodeURIComponent(app.masterId) + '&lip=' + ip + '&start=' + startFlag;
  var req = http.get(url, function(res) {
    // output response body
    res.setEncoding('utf8');
    res.on('data', function(str) {
      // console.log(str);
    });
  });
  req.on("error", function(err) {

  });
}

