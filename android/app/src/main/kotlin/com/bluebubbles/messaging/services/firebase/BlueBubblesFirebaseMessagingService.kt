package com.bluebubbles.messaging.services.firebase

import com.bluebubbles.messaging.Constants
import com.bluebubbles.messaging.services.backend_ui_interop.DartWorkManager
import com.bluebubbles.messaging.utils.PersistentLog
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class BlueBubblesFirebaseMessagingService: FirebaseMessagingService() {
    override fun onCreate() {
        super.onCreate()
        PersistentLog.d(applicationContext, Constants.logTag, "FCM service created")
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val type = message.data["type"] ?: return
        PersistentLog.d(applicationContext, Constants.logTag, "Received new message of type $type from FCM...")
        DartWorkManager.createWorker(applicationContext, type, HashMap(message.data)) {}

        TaskerEventSender.send(applicationContext, type, message.data)
    }
}