var app = require('../app.js');
var def = require('../define.js');
var express = require('express');
var request = require('request');
var router = express.Router();

router.get('/', function(req, res, next) {
  res.render('login.html', {userName : '', error: null});
});

router.post('/', function(req, res, next) {
  if (req.body.userName.length  == 0 || req.body.password.length == 0) {
    var err = '入力が正しくありません。確認して再入力してください。';
    res.render('login.html', {userName: req.body.userName, error: err});
    return;
  }
  process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
  var options = {
    uri: def.AMI_DOMAIN + "delegator/login",
    method: 'POST',
    headers: {
      "Content-type": "application/json"
    },
    json: true,
    form: {
      "token": app.amiToken,
      "master_id": app.masterId,
      "login_id": req.body.userName,
      "password": req.body.password
    }
  };
  request(options, function(error, response, body) {
    if (!error && response.statusCode == 200) {
      if (body.status == 'OK') {
        req.session.user = {name: req.body.userName};
        res.redirect('/admin');
        return;
      }
    }
    res.render('login.html', {userName: req.body.userName, error: 'ログインIDまたはパスワードが正しくありません。'});
  });
});

module.exports = router;
