package com.bluebubbles.messaging

import com.bluebubbles.messaging.services.backend_ui_interop.DartWorkManager
import com.bluebubbles.messaging.services.firebase.TaskerEventSender
import com.bluebubbles.messaging.utils.PersistentLog
import com.google.gson.Gson
import com.google.gson.JsonElement
import com.google.gson.reflect.TypeToken

import org.unifiedpush.android.connector.MessagingReceiver
import io.flutter.embedding.engine.dart.DartExecutor

import android.app.PendingIntent
import android.content.Context
import android.os.Bundle

class UnifiedPushReceiver : MessagingReceiver() {
    companion object {
        const val tag: String = "UnifiedPushReceiver"
    }

    override fun onNewEndpoint(context: Context, endpoint: String, instance: String) {
        PersistentLog.d(context, tag, "New endpoint: $endpoint")

        val data = HashMap<String, Any?>();
        data["endpoint"] = endpoint;
        DartWorkManager.createWorker(context, "unifiedpush-settings", data) {}
    }

    override fun onRegistrationFailed(context: Context, instance: String) {
        PersistentLog.d(context, tag, "Registration Failed")
        val data = HashMap<String, Any?>();
        data["endpoint"] = "";
        DartWorkManager.createWorker(context, "unifiedpush-settings", data) {}
    }

    override fun onUnregistered(context: Context, instance: String) {
        PersistentLog.d(context, tag, "Unregistered endpoint")
        val data = HashMap<String, Any?>();
        data["endpoint"] = "";
        DartWorkManager.createWorker(context, "unifiedpush-settings", data) {}
    }

    inline fun <reified T> Gson.fromJson(json: String) = fromJson<T>(json, object: TypeToken<T>() {}.type)

    override fun onMessage(context: Context, payload: ByteArray, instance: String) {
        val applicationContext = context.getApplicationContext()
        val msg = payload.toString(Charsets.UTF_8)
        val gson: Gson = Gson()
        val json: Map<String, JsonElement> = gson.fromJson(msg)
        val type: String
        try {
            type = json.get("type")?.getAsString() ?: return
        } catch (e: UnsupportedOperationException) {
            PersistentLog.d(applicationContext, tag, "Invalid message type")
            return
        }

        PersistentLog.i(applicationContext, tag, "Received new message of type $type from UnifiedPush...")
        DartWorkManager.createWorker(applicationContext, type, HashMap(json)) {}

        TaskerEventSender.send(applicationContext, type, json.mapValues { (_, value) ->
            if (value.isJsonPrimitive) value.asString else value.toString()
        })
    }
}