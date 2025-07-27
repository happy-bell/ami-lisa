var path = require('path');
var express = require('express');
var app = express();
var cookieParser = require('cookie-parser');
var bodyParser = require('body-parser');
var session = require('express-session');
const { exec } = require('child_process');
var apps = require('./app.js');

var routes = require('./routes/index');
var admin = require('./routes/admin');
var login = require('./routes/login');

var currentDir = __dirname;
var webDir = path.dirname(__dirname) + '/web';
var viewDir = currentDir + '/views';

app.set('views', viewDir);
app.set('view engine', 'ejs');
app.engine('html', require('ejs').renderFile);

app.use(cookieParser());
app.use(bodyParser.urlencoded({extended: true}));
app.use(express.static(webDir));
app.use(session({
  secret: 'aJ9scE8cvjl1',
  resave: false,
  saveUninitialized: true,
  cookie: {
    httpOnly: true,
    maxAge: 30 * 60 * 1000 // 30min.
  }
}));

app.get('/reboot/:token', function(req, res, next) {
  if (req.params.token == 'hP5ppMqMwGeQ6Gh5MUAz7ZaBQT8WedxZ') {
    exec('cd ' + apps.scriptDir, (err, stdout, stderr) => {
        if (err) {
          console.log(`stderr: ${stderr}`)
          return
        }
        exec('forever restart ' + apps.scriptName);
      }
    );
    res.json({'status': 'ok'});
    return;
  }
  res.json({'status': 'ng'});
});

app.get('/auto_receives/:udid/:token', function(req, res, next) {
  if (req.params.token != 'hP5ppMqMwGeQ6Gh5MUAz7ZaBQT8WedxZ') {
    res.json({'status': 'ng'});
    return;
  }
  var toClient = apps.getClient(req.params.udid);
  // console.log(req.params.udid, toClient);
  if (toClient != null) {
    toClient.socket.emit("app", {message: "auto_receives"});
  }
  res.json({'status': 'ok'});
});

app.get('/pushsensor/:token', function(req, res, next) {
  if (req.params.token == 'hP5ppMqMwGeQ6Gh5MUAz7ZaBQT8WedxZ') {
    var toGroup = req.query.GID;
    var title = req.query.title;
    var message = req.query.message;
    if (toGroup.length > 0) {
      apps.pushToGroupTitle(toGroup, message, title);
    }
    res.json({'status': 'ok'});
    return;
  }
  res.json({'status': 'ng'});
});

app.post('/psensor', function(req, res, next) {
  if (req.body.token != 'hP5ppMqMwGeQ6Gh5MUAz7ZaBQT8WedxZ') {
    console.log(req.body);
    res.json({'status': 'ng1'});
    return;
  }
  var toGroup = req.body.GID;
  var title = req.body.title;
  var message = req.body.message;
  if (toGroup.length > 0) {
    apps.pushToGroupTitle(toGroup, message, title);
  }
  res.json({'status': 'ok'});
});

var sessionCheck = function(req, res, next) {
  if (req.session.user) {
    next();
  } else {
    res.redirect('/login');
  }
};

app.use('/login', login);
app.use('/', routes);

//app.use('/admin', admin);
app.use('/admin', sessionCheck, admin);


app.use(function(req, res, next) {
  res.sendFile(webDir + '/404.html');
  //var error = new Error('Cannot ' + req.method + ' ' + req.path);
  //error.status = 404;
  //next(error);
});

module.exports = app;
