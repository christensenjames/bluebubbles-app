package com.bluebubbles.messaging.services.firebase

import android.content.Context
import android.content.Intent
import androidx.core.os.bundleOf
import com.bluebubbles.messaging.utils.Utils
import io.flutter.plugin.common.MethodChannel

object TaskerEventSender {
    fun send(context: Context, type: String, data: Map<String, Any?>) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", 0)
        if (!prefs.getBoolean("sendEventsToTasker", false)) return

        Utils.getServerUrl(context, object : MethodChannel.Result {
            override fun success(result: Any?) {
                val intent = Intent("net.dinglisch.android.taskerm.BB_EVENT")
                    .setPackage("net.dinglisch.android.taskerm")
                    .putExtras(bundleOf(*data.toList().toTypedArray()))
                    .putExtra("url", result.toString())
                    .putExtra("event", type)
                context.sendBroadcast(intent)
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
            override fun notImplemented() {}
        })
    }
}
