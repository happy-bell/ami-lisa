const { initializeApp } = require('firebase-admin/app');
const admin = require('firebase-admin');
var path = require('path');
const serviceAccount = require('/var/ssl/frinurse-firebase.json');

const app = admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: "https://frinurse.firebaseio.com"
});

const registrationTokens = [
  'fc3dm7UcqUVdhLTqcEXMDT:APA91bEkW5tmpqIGYfRoJW9rI9Gciw8x09oyxHXm1KVGfg04QY4GrOAfUjtB6t9403Mmg59m0GCqtCqDiuXCM18MhrFN8zGpMaPbLJJle5bi86rkQpgs3RlSjI5pK9hCJu-tGm3Z_6A1'
];
// const token ='fSu5Xv_ZiUR3q7knl8Xpf9:APA91bECXFQvh3Y5GrVb-jl_MeDk9mduinNQ18wkQ5RErhJ2Fo4V516QWV4m-AmLTGkkp-F16nw6YJPNZu-fpRe-oT63CtWhADRgPFnWQS_tpGhDJXtkFedG0Ry7hZq8F3zISRUEiHKx';
const token ='dqu7l4ZjZkcihS19cF1yvx:APA91bFt1NBAv8mUfbOpYT0IDbcMCUztAeizyhXnSKUB9UhtEnO_DBxq5-cXXMHUH7ZY116E7yR-DYXYR3kaDwPK5O_zr1G0qUvuACeoEmh0ZIp1sTw2ITSkdQdFT-fTeEAQd7l50Oix';
const title = 'title';
const message = 'メッセージ';
const msg = {
  notification: {
    title: title,
    body: 'body',
  },
  data: {"click_action": "FLUTTER_NOTIFICATION_CLICK"},
  token,
  android: {
    priority: "high",
    notification: {
      sound: "ringring.wav",
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
app.messaging().send(msg).then(
  res => console.log({res})
).catch(
  err => console.error({err})
);
