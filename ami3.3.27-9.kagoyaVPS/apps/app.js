var address = require('../config/address.json');
var Client = require('./client.js');
var gcm = require('node-gcm');
var mongoose = require('mongoose');
const path = require("path");
const admin = require('firebase-admin');
mongoose.Promise = Promise;

var addressSchema = new mongoose.Schema({
  "BOOK_GRP" : String,
  "TARGET_ID": String,
  "NAME": String
});

var callbuttonSchema = new mongoose.Schema({
  "BUTTON_ID": String,
  "BOOK_GRP" : String,
  "TARGET_ID": String,
  "NAME": String
});

var app = (function () {
  this.ip = '';
  this.io = null;
  this.db = null;
  this.mcs = {};
  this.addressModel = null;
  this.callButtonModel = null;
  this.productName = '';
  this.clients = {};
  this.pushmap = {};
  this.addressList = address['ADDRESS'];
  this.addressIDList = {};
  this.groupCalling = {};
  this.gcmApiKey = '';
  this.gcmSender = null;
  this.masterId = '';
  this.amiToken = '';
  //var obj = require('./config/address.json');
  //var addressList = obj["ADDRESS"];
  this.scriptName = '';
  this.scriptDir = '';
  this.firebaseJsonPath = '';
  this.fapp = null;
  this.setIO = function(io) {
    this.io = io;
  };

  this.setDB = function(db) {
    this.db = db;
    this.setDBModel();
  };

  this.setDBModel = function() {
    this.addressModel = this.db.model('address', addressSchema);
    this.callButtonModel = this.db.model('callbutton', callbuttonSchema);
  };

  this.setGcmApiKey = function(key) {
    this.gcmApiKey = key;

    if (this.gcmApiKey.length > 0) {
      this.gcmSender = new gcm.Sender(this.gcmApiKey);
    }
  }

  this.groupcast = function(group, event, data) {
    this.io.to(group).emit(event, data);
  };

  this.broadcast = function(event, data) {
    this.io.sockets.emit(event, data);
  };

  this.addClient = function(socket, data) {
    if (this.pushmap[data.MYID]) {
      delete this.pushmap[data.MYID];
    }
    if (data.FIRTOKEN) {
      this.pushmap[data.MYID] = {
        group: data.GROUP,
        token: data.FIRTOKEN,
        codes: []
      };
      if (typeof data.CODES !== 'undefined') {
        for (var i = 0; i < data.CODES.length; i++) {
          if (data.GROUP === data.CODES[i]) {
            continue;
          }
          this.pushmap[data.MYID]['codes'].push(data.CODES[i]);
        }
      }
    }

    this.clients[socket.id] = new Client(socket, data);
    return this.clients[socket.id];
  };

  this.delClient = function(client) {
    if (this.pushmap[client.udid]) {
      delete this.pushmap[client.udid];
    }
    delete this.clients[client.socket.id];
  };

  this.getClient = function(udid) {
    for (var sockID in this.clients) {
      if (this.clients[sockID].udid == udid) {
        return this.clients[sockID];
      }
    }
    return null;
  };

  this.loadAddressList = function() {
    var that = this;
    var i;

    this.setAddressIDList();

    this.addressModel.find({}, null, {sort: {'_id': 1}}, function(err , datas) {
      for (i = 0, size = datas.length; i < size; i++) {
        if (i == 0) {
          console.log('load address list from db');
          that.addressList = [];
        }
        that.addressList.push(datas[i]);
      }
      that.setAddressIDList();
    });
  };

  this.setAddressIDList = function() {
    var that = this;
    this.addressIDList = {};
    this.addressList.forEach(function(val, index) {
      if (val["TARGET_ID"] in that.addressIDList) {
        return;
      }
      that.addressIDList[val["TARGET_ID"]] = val["NAME"];
    });
  };

  this.getAddressIDName = function(udid) {
    if (udid in this.addressIDList) {
      return this.addressIDList[udid];
    }
    return '';
  };

  this.delAddressList = function() {
    this.addressModel.remove({}, function(err) {});
  };

  this.addAddressList = function(address, cb) {
    var addressData = new this.addressModel();
    addressData["BOOK_GRP"] = address["BOOK_GRP"];
    addressData["TARGET_ID"] = address["TARGET_ID"];
    addressData["NAME"] = address["NAME"];
    addressData.save(function(err) {
      if (typeof cb !== 'undefined') {
        cb();
      }
    });
  };

  this.initializeFirebaseApp = function() {
    const serviceAccount = require(this.firebaseJsonPath);

    this.fapp = admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      databaseURL: "https://frinurse.firebaseio.com"
    });
  };

  this.pushToUdid = function(udid1, message) {
    //console.log(udid1, message, this.pushmap);
    var that = this;
    var deviceTokens = [];

    Object.keys(this.pushmap).forEach(function(udid) {
      if (udid1 == udid) {
        deviceTokens.push(that.pushmap[udid].token);
      }
    });
    this.pushNotification(deviceTokens, message, '[M001]:呼び出し');
  };

  this.pushToGroup = function(group, message) {
    console.log(group, message, this.pushmap);
    var that = this;
    var deviceTokens = [];
    Object.keys(this.pushmap).forEach(function(udid) {
      if (group == that.pushmap[udid].group) {
        console.log('push => ' + udid);
        deviceTokens.push(that.pushmap[udid].token);
      } else if (that.pushmap[udid].codes.indexOf(group) !== -1) {
        console.log('push indexof => ' + udid);
        deviceTokens.push(that.pushmap[udid].token);
      } else {
        console.log('push iterator => ' + udid);
        for (var i = 0; i < that.pushmap[udid].codes.length; i++) {
          console.log('push => [' + group + ']:[' + that.pushmap[udid].codes[i] + ']');
          if (group == that.pushmap[udid].codes[i]) {
            deviceTokens.push(that.pushmap[udid].token);
          }
        }
      }
    });
    this.pushNotification(deviceTokens, message, '[M001]:緊急呼び出し');
  };

  this.pushToGroupTitle = function(group, message, title) {
    //console.log(group, message, this.pushmap);
    var that = this;
    var deviceTokens = [];
    Object.keys(this.pushmap).forEach(function(udid) {
      if (group == that.pushmap[udid].group) {
        deviceTokens.push(that.pushmap[udid].token);
      }
    });
    this.pushNotification(deviceTokens, message, title);
  };

  this.pushNotification = function(deviceTokens, message, title) {
    for (var i = 0; i < deviceTokens.length; i++) {
      this.sendGcm(deviceTokens[i], message, title);
    }
  }

  this.sendGcm = function(token, message, title) {
    const msg = {
      notification: {
        title: title,
        body: message,
      },
      data: {"title": title, "body": message, "click_action": "FLUTTER_NOTIFICATION_CLICK"},
      token,
      android: {
        priority: "high",
        notification: {
		title: title, body: message,
          sound: "ringring.mp3",
        },
      },
      apns: {
        payload: {
          aps: {
            contentAvailable: true,
            sound: "ringring.wav",
          },
        },
      },
    };
    this.fapp.messaging().send(msg).then(
      res => console.log({res})
    ).catch(
      err => console.error({err})
    );
  }

  this.pushNotificationOld = function(deviceTokens, message, title) {
    if (this.gcmApiKey.length == 0) {
      return;
    }
    var gcmMessage = new gcm.Message({
      notification: {
        title: title,
        body: message,
        sound: "ringring.wav",
        data: {"title": title, "message": message, "click_action": "FLUTTER_NOTIFICATION_CLICK"}
      },
      android: {
        notification: {
          sound: "ringring.wav"
        }
      },
      data: {"title": title, "message": message}
    });
    this.gcmSender.sendNoRetry(gcmMessage, { registrationTokens: deviceTokens }, function (err, response) {
      if (err) {
        // console.error(err);
      } else {
        // console.log(response);
      }
    });
  };

  this.pushTest = function(deviceToken, title, message) {
    this.pushNotification([deviceToken], message, title);
    return;
    if (this.gcmApiKey.length == 0) {
      return;
    }
    var gcmMessage = new gcm.Message({
      notification: {
        title: title,
        body: message,
        sound: "ringring.wav",
        data: {"title": title, "message": message, "click_action": "FLUTTER_NOTIFICATION_CLICK"}
      }
    });
    this.gcmSender.sendNoRetry(gcmMessage, { registrationTokens: [deviceToken] }, function (err, response) {
      if (err) {
        // console.error(err);
      } else {
        // console.log(response);
      }
    });
  };



  this.getLocalIP = function() {
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
    this.ip = ret;
  };

  return this;
})();

module.exports = app;
