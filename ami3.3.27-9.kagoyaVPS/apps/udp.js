var app = require('./app.js');
var def = require('./define.js');

module.exports = function(sock, data, peer) {
  //var key = peer.address + ":" + peer.port;
  var command = data.toString('ascii', 0, 4);
  var client, udid, toClient;
  var i, id;

  if (command == 'echo') {
    sock.send(data, 0, data.length, peer.port, peer.address);
  }

  if (command == 'ET::') {
    udid = data.toString('utf8', 4, data.length);
    client = app.getClient(udid);
    if (client) {
      console.log("receive udp entry:", client.udid);
      client.udpIP = peer.address;
      client.udpPort = peer.port;
      sock.send('entried', 0, 7, client.udpPort, client.udpIP);
    }
    return;
  }

  udid = data.toString('utf8', 4, 15).trim();
  client = app.getClient(udid);
  if (client == null) {
    return;
  }

  if (command == 'VIM:' || command == 'VCM:' || command == 'AIM:') {
    if (client.hasOwnProperty('udpIP') && client.udpIP.length > 0) {
      sock.send(data, 0, data.length, client.udpPort, client.udpIP);
    }
  }
  else if (command == 'AI::') {
    for (i = 0; i < client.talkTo.length; i++) {
      toClient = app.getClient(client.talkTo[i].udid);
      if (toClient) {
        if (toClient.udpIP.length > 0) {
          //console.log(command + ' ' + udid + ' -> ' + toClient.udid + '(' + toClient.udpIP + ':' + toClient.udpPort);
          //app.groupcast('log', 'udp', command + ' ' + udid + ' -> ' + toClient.udid + '(' + toClient.udpIP + ':' + toClient.udpPort);
          sock.send(data, 0, data.length, toClient.udpPort, toClient.udpIP);
        }
      }
    }
  }
  else if (command == 'VI::' || command == 'VC::' || command == 'IM::') {
    if (client.status == def.ECLIENT_STATUS.CLIENT_STATUS_LIVE) {
      for (id in app.clients) {
        toClient = app.clients[id];
        if (toClient == null || toClient.udid == udid) {
          continue;
        }
        if (toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_STAND || toClient.status == def.ECLIENT_STATUS.CLIENT_STATUS_HOLD) {
          //console.log(command + ' ' + udid + ' -> ' + toClient.udid + '(' + toClient.udpIP + ':' + toClient.udpPort);
          if (toClient.udpIP.length > 0) {
            sock.send(data, 0, data.length, toClient.udpPort, toClient.udpIP);
          }
        }
      }
      return;
    }

    for (i = 0; i < client.safetyCheck.length; i++) {
      toClient = app.getClient(client.safetyCheck[i]);
      if (toClient) {
        if (toClient.udpIP.length > 0) {
          sock.send(data, 0, data.length, toClient.udpPort, toClient.udpIP);
        }
      }
    }

    for (i = 0; i < client.talkTo.length; i++) {
      toClient = app.getClient(client.talkTo[i].udid);
      if (toClient) {
        if (toClient.udpIP.length > 0) {
          //app.groupcast('log', 'udp', command + ' ' + udid + ' -> ' + toClient.udid + '(' + toClient.udpIP + ':' + toClient.udpPort);
          //console.log('VI ' + udid + ' -> ' + toClient.udid + '(' + toClient.udpIP + ':' + toClient.udpPort);
          sock.send(data, 0, data.length, toClient.udpPort, toClient.udpIP);
        }
      }
    }
  }
};