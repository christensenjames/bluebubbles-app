package com.bluebubbles.messaging.services.filesystem

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ext.SdkExtensions
import android.provider.MediaStore
import android.provider.OpenableColumns
import com.bluebubbles.messaging.Constants
import com.bluebubbles.messaging.MainActivity
import com.bluebubbles.messaging.models.MethodCallHandlerImpl
import com.bluebubbles.messaging.services.backend_ui_interop.MethodCallHandler
import com.bluebubbles.messaging.utils.PersistentLog
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class PickImagesHandler : MethodCallHandlerImpl() {
    companion object {
        const val tag: String = "pick-images"

        fun onActivityResult(context: Context, resultCode: Int, data: Intent?) {
            val result = MethodCallHandler.consumePickImagesResult() ?: return
            if (resultCode != Activity.RESULT_OK || data == null) return result.success(emptyList<String>())
            val uris = mutableListOf<Uri>()
            data.clipData?.let {
                for (i in 0 until it.itemCount) it.getItemAt(i).uri?.let(uris::add)
            } ?: data.data?.let(uris::add)
            if (uris.isEmpty()) return result.success(emptyList<String>())
            copyUrisOffThread(context, uris, result)
        }
    }

    override fun handleMethodCall(call: MethodCall, result: MethodChannel.Result, context: Context) {
        val allowedTypes = arrayOf("image/jpeg", "image/png", "image/gif", "image/webp", "image/heic", "image/heif")
        val usePhotoPicker = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) >= 2)
        val intent = if (usePhotoPicker) {
            Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                type = "image/*"
                putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, MediaStore.getPickImagesMaxLimit())
                putExtra(Intent.EXTRA_MIME_TYPES, allowedTypes)
            }
        } else {
            Intent(Intent.ACTION_GET_CONTENT).apply {
                type = "image/*"
                putExtra(Intent.EXTRA_MIME_TYPES, allowedTypes)
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                addCategory(Intent.CATEGORY_OPENABLE)
            }
        }
        try {
            MethodCallHandler.setPickImagesResult(result)
            (context as MainActivity).startActivityForResult(intent, Constants.pickImagesRequestCode)
        } catch (e: Exception) {
            MethodCallHandler.consumePickImagesResult()
            result.error("500", "Failed to launch image picker", e.localizedMessage)
        }
    }
}

private fun copyUrisOffThread(context: Context, uris: List<Uri>, result: MethodChannel.Result) {
    val mainHandler = Handler(Looper.getMainLooper())
    Thread {
        try {
            val dir = File(context.cacheDir, "picked_images").apply { if (!exists()) mkdirs() }
            val paths = uris.mapIndexed { index, uri ->
                val displayName = File(getDisplayName(context, uri)).name
                val fileName = displayName.takeUnless { it.isEmpty() || it == "." || it == ".." } ?: "image"
                val pickDir = File(dir, "${System.nanoTime()}_$index").apply { mkdirs() }
                val dest = File(pickDir, fileName)
                context.contentResolver.openInputStream(uri)?.use { input ->
                    dest.outputStream().use { input.copyTo(it) }
                } ?: throw IllegalStateException("Cannot open $uri")
                dest.absolutePath
            }
            mainHandler.post { result.success(paths) }
        } catch (e: Exception) {
            PersistentLog.e(context, Constants.logTag, "Failed to copy picked images", e)
            mainHandler.post { result.error("500", "Failed to copy picked images", e.localizedMessage) }
        }
    }.start()
}

private fun getDisplayName(context: Context, uri: Uri): String {
    if (uri.scheme == "content") {
        try {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) {
                    val idx = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx != -1) it.getString(idx)?.takeIf { n -> n.isNotEmpty() }?.let { n -> return n }
                }
            }
        } catch (_: Exception) {}
    }
    return uri.lastPathSegment ?: "image"
}
