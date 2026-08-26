package jp.amiplus.lisa

import android.os.Bundle
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * 一部の Google TV は C2DM ではなく MESSAGING_EVENT だけ届く。
 * Flutter 側 Service の onMessageReceived は空なので、ここでネイティブ着信する（メーカー不問）。
 */
class AmiFirebaseMessagingService : FlutterFirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val extras = Bundle()
        for ((k, v) in message.data) {
            extras.putString(k, v)
        }
        message.notification?.title?.let {
            extras.putString("gcm.notification.title", it)
            extras.putString("title", it)
        }
        message.notification?.body?.let {
            extras.putString("gcm.notification.body", it)
            extras.putString("body", it)
        }
        AmiIncomingFcmReceiver.handleIncoming(applicationContext, extras)
        super.onMessageReceived(message)
    }
}
