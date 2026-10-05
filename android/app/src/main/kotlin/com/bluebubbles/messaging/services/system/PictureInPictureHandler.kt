package com.bluebubbles.messaging.services.system

import android.content.Context
import android.content.pm.PackageManager
import android.util.Rational
import com.bluebubbles.messaging.MainActivity
import com.bluebubbles.messaging.models.MethodCallHandlerImpl
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class PictureInPictureHandler : MethodCallHandlerImpl() {
    companion object {
        const val supportedTag = "pip-supported"
        const val enterTag = "pip-enter"
        const val autoEnterTag = "pip-auto-enter"

        private const val ratioScale = 10_000.0
        private const val minRatioNumerator = 4_185
        private const val maxRatioNumerator = 23_900
    }

    override fun handleMethodCall(call: MethodCall, result: MethodChannel.Result, context: Context) {
        when (call.method) {
            supportedTag -> result.success(isSupported(context))
            enterTag -> enterPictureInPicture(call, result, context)
            autoEnterTag -> setAutoEnter(call, result, context)
        }
    }

    private fun isSupported(context: Context): Boolean {
        return context.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun enterPictureInPicture(call: MethodCall, result: MethodChannel.Result, context: Context) {
        val activity = context as? MainActivity
        val ratio = aspectRatio(call)
        if (activity == null || ratio == null || !isSupported(context)) {
            result.success(null)
            return
        }

        val params = android.app.PictureInPictureParams.Builder()
            .setAspectRatio(ratio)
            .build()
        activity.enterPictureInPictureMode(params)
        result.success(null)
    }

    private fun setAutoEnter(call: MethodCall, result: MethodChannel.Result, context: Context) {
        val activity = context as? MainActivity
        if (activity != null) {
            val enabled = call.argument<Boolean>("enabled") == true
            activity.configurePipAutoEnter(enabled && isSupported(context), aspectRatio(call))
        }
        result.success(null)
    }

    private fun aspectRatio(call: MethodCall): Rational? {
        val ratio = call.argument<Double>("aspectRatio")?.takeIf { it.isFinite() && it > 0 } ?: return null
        return Rational((ratio * ratioScale).roundToInt().coerceIn(minRatioNumerator, maxRatioNumerator), ratioScale.toInt())
    }
}
