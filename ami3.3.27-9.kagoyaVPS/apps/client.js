var def = require('./define.js');

module.exports = Client;

function Client(socket, args) {
  this.socket = socket;
  this.status = def.ECLIENT_STATUS.CLIENT_STATUS_STAND;
  this.udid = args.MYID;
  this.code = args.DELEGATOR;
  this.name = args.NAME;
  this.id = socket.id;
  this.group = args.GROUP;
  this.dispSize = args.DISPSIZE;
  this.marker = args.MARKER;
  this.udpIP = "";
  this.udpPort = 0;
  this.safetyCheck = [];
  this.callToGroup = "";
  this.callTo = [];
  this.talkTo = [];
  this.holdTo = {};
  this.holdFrom = {};
  this.record = {};
  this.firToken = args.FIRTOKEN || "";

  if (args.USETYPE == "1") {
      this.status = def.ECLIENT_STATUS.CLIENT_STATUS_LIVE;
  }

  if (!this.name) {
    console.log('acount');
    this.name = 'アカウント';
  }
}

Client.prototype.toStatusDic = function() {
    return {
        "status": this.status.toString(),
        "udid": this.udid,
        "code": this.code,
        "name": this.name,
        "group": this.group,
        "dispSize": this.dispSize,
        "marker": this.marker,
        "udpIP": this.udpIP,
        "udpPort": this.udpPort,
        "firToken": this.firToken
    };
};

Client.prototype.delSafetyCheck = function(udid) {
    var idx = -1;
    for (var i = 0; i < this.safetyCheck.length; i++) {
        if (this.safetyCheck[i] == udid) {
            idx = i;
            break;
        }
    }
    
    if (idx >= 0) {
        this.safetyCheck.splice(idx, 1);
    }
};

Client.prototype.hasHoldTo = function() {
  if (this.holdTo.udid) {
    if (this.holdTo.udid.length > 0) {
      return true;
    }
  }
  return false;
};

Client.prototype.hasHoldFrom = function() {
  if (this.holdFrom.udid) {
    if (this.holdFrom.udid.length > 0) {
      return true;
    }
  }
  return false;
};

Client.prototype.isHolded = function(udid) {
  if (this.holdFrom.udid) {
    if (this.holdFrom.udid == udid) {
      return true;
    }
  }
  return false;
};

Client.prototype.delCallTo = function(callTo) {
    var idx = -1;
    for (var i = 0; i < this.callTo.length; i++) {
        if (this.callTo[i] == callTo) {
            idx = i;
            break;
        }
    }
    
    if (idx >= 0) {
        this.callTo.splice(idx, 1);
    }
};

Client.prototype.isCallTo = function(callTo) {
    for (var i = 0; i < this.callTo.length; i++) {
        if (this.callTo[i] == callTo) {
            return true;
        }
    }
    return false;
};

Client.prototype.getTalkTo = function(talkTo) {
  for (var i = 0; i < this.talkTo.length; i++) {
    if (this.talkTo[i].udid == talkTo) {
      return this.talkTo[i];
    }
  }
  return null;
};

Client.prototype.delTalkTo = function(talkTo) {
    var idx = -1;
    for (var i = 0; i < this.talkTo.length; i++) {
        if (this.talkTo[i].udid == talkTo) {
            idx = i;
            break;
        }
    }
    
    if (idx >= 0) {
        this.talkTo.splice(idx, 1);
    }
};

Client.prototype.isTalkTo = function(talkTo) {
    for (var i = 0; i < this.talkTo.length; i++) {
        if (this.talkTo[i].udid == talkTo) {
            return true;
        }
    }
    return false;
};
