var app = require('../app.js');
var def = require('../define.js');
var express = require('express');
var request = require('request');
var router = express.Router();

router.get('/', function (req, res, next) {
  res.render('index.html', {title: 'タイトル'});
});

router.get('/address_list', function (req, res, next) {
  var reqMCS = req.query.mcs !== undefined;
  var address = [];
  if (reqMCS) {
    var options = {
      uri: def.MCS_DOMAIN + "delegator/address_list.php",
      qs: {
        "id": encodeURI(app.productName)
      }
    };
    request.get(options, function(error, response, body) {
      if (!error && response.statusCode == 200) {
        bodyJson = JSON.parse(body);
        address = bodyJson.address;
      }
      res.render('address_list.html', {address: address, mcs: '1'});
    });
    return;
  } else {
    app.addressList.forEach(function(val, index) {
      address.push(val);
    });
  }

  res.render('address_list.html', {address: address, mcs: '0'});
});

router.get('/client_list', function (req, res, next) {
  res.render('client_list.html');
});

router.get('/callbutton_list', function (req, res, next) {
  res.render('callbutton_list.html');
});

router.get('/push_list', function (req, res, next) {
  res.render('push_list.html');
});

router.get('/view_log', function (req, res, next) {
  res.render('view_log.html');
});

router.post('/update_address', function (req, res, next) {
  var options = {
    uri: def.MCS_DOMAIN + "delegator/address_list.php",
    qs: {
      "id": app.productName
    }
  };
  var redirectTo = '/admin/address_list';
  var address;
  var count;
  var cb;
  request.get(options, function(error, response, body) {
    if (!error && response.statusCode == 200) {
      bodyJson = JSON.parse(body);
      address = bodyJson.address;
      count = address.length;

      app.delAddressList();
      if (count == 0) {
        res.redirect(redirectTo);
      }

      for (var i = 0; i < count; i++) {
        bookGrp = address[i]['BOOK_GRP'];
        targetID = address[i]['TARGET_ID'];
        name = address[i]['NAME'];
        if (i + 1 == count) {
          isLoad = true;
          cb = function(){
            app.loadAddressList();
            res.redirect(redirectTo);
          };
        }
        app.addAddressList({"BOOK_GRP": bookGrp, "TARGET_ID": targetID, "NAME": name}, cb);
      }
    } else {
      res.redirect(redirectTo);
    }
  });
});

router.get('/push_test', function (req, res, next) {
  app.pushToGroup('STAFF', "緊急呼び出し【P001】");
  res.json({"STATUS": "OK"});
});

module.exports = router;
