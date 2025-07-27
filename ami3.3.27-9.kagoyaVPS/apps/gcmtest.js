var gcm = require('node-gcm');
var key = 'AAAAfNk0cGs:APA91bEA4HC43hPgN9BbowyXMjTqp75f-vRuLaD_rrBfB2WP3xyaiW3yyOw14NCYSCnbk6gesdNYHSkJGMJacRBxHyIGHzhTgULr_w6kbUzM_SskMx3yEkZbYynnhvicbtD82jYKygzp';
//var key = 'AAAAytkcsnk:APA91bH9jX1e-i-f_GvZAgaXcmjjPTmRu1BPR88LxfhdXmwh8Q9RobijMRgg4MQx7Tx8aHuUPQIiAV9ZQSBwesL8F6dLeFKhds6i53QlOTlW5AMdRrNSrf9NKppBHpeLdiGyzdkU66v0';
var deviceTokens = ['fMgN1xg6Wsw:APA91bHTO_pE_MLzNHZmtnQr7pcPX1xNFeyJ7tphPPNgfHF5_bmhtiBDDiJuEGfvDsAaA2eCmcwhgpJCMj_8ksZPfHYyD4cotjbMDRKD9IaNsUrLJh-SrBO6AClr0uwd72S-6cmbOjLp'];

var gcmMessage = new gcm.Message({
  notification: {
    title: 'タイトル',
    body: '通知内容',
    sound: "canon.m4a"

  },
  apns: {
    aps: {
      "badge": 1,
      "sound": "canon.m4a"
    }
  }
});
var gcmSender = new gcm.Sender(key);

gcmSender.sendNoRetry(gcmMessage, { registrationTokens: deviceTokens }, function (err, response) {
  if (err) {
    console.error(err);
  } else {
    console.log(response);
  }
});

