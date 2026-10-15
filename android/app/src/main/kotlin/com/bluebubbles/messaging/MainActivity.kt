package com.bluebubbles.messaging

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.util.Rational
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsAnimation
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import androidx.activity.ComponentActivity
import androidx.annotation.RequiresApi
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.Lifecycle
import com.bluebubbles.messaging.services.backend_ui_interop.MethodCallHandler
import com.bluebubbles.messaging.services.filesystem.PickImagesHandler
import com.bluebubbles.messaging.services.foreground.ForegroundServiceBroadcastReceiver
import com.bluebubbles.messaging.Constants
import com.bluebubbles.messaging.utils.PersistentLog
import com.google.firebase.firestore.FirebaseFirestoreException
import io.flutter.embedding.android.FlutterFragment
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var pipModeActive = false
    private val pipActivityResumed get() = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
    private var pipAutoEnterEnabled = false
    private var pipExitPending = false
    private var pipDismissedSent = false
    private var pipAspectRatio = Rational(16, 9)

    companion object {
        private val engineLock = Any()
        @Volatile private var _engine: FlutterEngine? = null

        // Whether the Dart side of [_engine] has finished registering its method-call
        // handler (signaled via the "ready" method call — see MethodCallHandler).
        // Always reset to false alongside [_engine] itself so a stale "ready" from a
        // previous engine can never be mistaken for the current one's readiness.
        @Volatile private var _dartReady = false

        fun getEngine(): FlutterEngine? {
            synchronized(engineLock) {
                return _engine
            }
        }

        fun setEngine(newEngine: FlutterEngine?, context: Context) {
            synchronized(engineLock) {
                PersistentLog.d(
                    context,
                    Constants.logTag,
                    "MainActivity engine ${if (newEngine != null) "set (${newEngine.hashCode()})" else "cleared"} — resetting dartReady to false"
                )
                _engine = newEngine
                _dartReady = false
            }
        }

        fun isDartReady(): Boolean {
            synchronized(engineLock) {
                return _dartReady
            }
        }

        fun setDartReady(ready: Boolean, context: Context) {
            synchronized(engineLock) {
                if (_dartReady != ready) {
                    PersistentLog.d(context, Constants.logTag, "MainActivity dartReady changing from $_dartReady to $ready")
                }
                _dartReady = ready
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) refeedImeInsetsAfterAnimation()
    }

    // Flutter replays stale IME insets after resuming mid-animation; re-feed the real ones past its listener.
    @RequiresApi(Build.VERSION_CODES.R)
    private fun refeedImeInsetsAfterAnimation() {
        val decor = window.decorView
        decor.setWindowInsetsAnimationCallback(object : WindowInsetsAnimation.Callback(DISPATCH_MODE_CONTINUE_ON_SUBTREE) {
            private var runningImeAnimations = 0
            override fun onPrepare(animation: WindowInsetsAnimation) {
                if (animation.typeMask and WindowInsets.Type.ime() == 0) return
                runningImeAnimations++
            }
            override fun onProgress(insets: WindowInsets, running: MutableList<WindowInsetsAnimation>) = insets
            override fun onEnd(animation: WindowInsetsAnimation) {
                if (animation.typeMask and WindowInsets.Type.ime() == 0) return
                // Re-feeding while another IME animation runs would snap the view to the final inset.
                if (--runningImeAnimations > 0) return
                decor.post {
                    if (runningImeAnimations > 0) return@post
                    val flutterView = findViewById<FlutterView>(FlutterFragment.FLUTTER_VIEW_ID) ?: return@post
                    flutterView.rootWindowInsets?.let { flutterView.dispatchApplyWindowInsets(it) }
                }
            }
        })
    }

    private var imeFocusProxy: ImeFocusProxy? = null
    private var imeVisibleOnFocusLoss = false

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        val flutterView = findViewById<FlutterView>(FlutterFragment.FLUTTER_VIEW_ID) ?: return
        if (!hasFocus) {
            imeVisibleOnFocusLoss =
                ViewCompat.getRootWindowInsets(flutterView)?.isVisible(WindowInsetsCompat.Type.ime()) == true
            return
        }
        if (!imeVisibleOnFocusLoss) return
        imeVisibleOnFocusLoss = false
        // The IMM reads the focused view right after this callback returns; FlutterView takes focus back a frame later.
        val proxy = imeFocusProxyFor(flutterView)
        proxy.isFocusable = true
        proxy.isFocusableInTouchMode = true
        proxy.requestFocus()
        window.decorView.post {
            flutterView.requestFocus()
            proxy.isFocusable = false
            proxy.isFocusableInTouchMode = false
        }
    }

    private fun imeFocusProxyFor(flutterView: FlutterView): ImeFocusProxy {
        imeFocusProxy?.takeIf { it.flutterView === flutterView }?.let { return it }
        imeFocusProxy?.let { (it.parent as? ViewGroup)?.removeView(it) }
        return ImeFocusProxy(this, flutterView).also {
            // Laid-out zero-size views cannot take focus (API 28+).
            (flutterView.parent as ViewGroup).addView(it, ViewGroup.LayoutParams(1, 1))
            imeFocusProxy = it
        }
    }

    // IME hides on refocus unless the focused view is a text editor; FlutterView never claims to be one.
    private class ImeFocusProxy(context: Context, val flutterView: FlutterView) : View(context) {
        init {
            isFocusable = false
            isFocusableInTouchMode = false
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) importantForAutofill = IMPORTANT_FOR_AUTOFILL_NO
        }

        override fun onCheckIsTextEditor() = true
        override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection? =
            flutterView.onCreateInputConnection(outAttrs)
        override fun checkInputConnectionProxy(view: View) = view === flutterView
        override fun dispatchKeyEvent(event: KeyEvent) = flutterView.dispatchKeyEvent(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        setEngine(flutterEngine, this)
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, Constants.methodChannel).setMethodCallHandler {
            call, result -> MethodCallHandler().methodCallHandler(call, result, this)
        }

        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            val cause = throwable.cause ?: throwable
            if (cause is FirebaseFirestoreException) {
                when (cause.code) {
                    FirebaseFirestoreException.Code.PERMISSION_DENIED ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: PERMISSION_DENIED — missing or insufficient security rules (${cause.message})", cause)
                    FirebaseFirestoreException.Code.UNAVAILABLE ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: UNAVAILABLE — service unreachable, check network connectivity (${cause.message})", cause)
                    FirebaseFirestoreException.Code.UNAUTHENTICATED ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: UNAUTHENTICATED — request not authenticated (${cause.message})", cause)
                    FirebaseFirestoreException.Code.NOT_FOUND ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: NOT_FOUND — document or collection does not exist (${cause.message})", cause)
                    FirebaseFirestoreException.Code.CANCELLED ->
                        PersistentLog.d(this, Constants.logTag, "Firestore: CANCELLED — listener was cancelled (${cause.message})")
                    FirebaseFirestoreException.Code.ALREADY_EXISTS ->
                        PersistentLog.w(this, Constants.logTag, "Firestore: ALREADY_EXISTS — document already exists (${cause.message})")
                    FirebaseFirestoreException.Code.RESOURCE_EXHAUSTED ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: RESOURCE_EXHAUSTED — quota exceeded (${cause.message})", cause)
                    FirebaseFirestoreException.Code.FAILED_PRECONDITION ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: FAILED_PRECONDITION — operation rejected, check indexes or state (${cause.message})", cause)
                    FirebaseFirestoreException.Code.ABORTED ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: ABORTED — transaction conflict or contention (${cause.message})", cause)
                    FirebaseFirestoreException.Code.INTERNAL ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: INTERNAL — internal server error (${cause.message})", cause)
                    FirebaseFirestoreException.Code.DEADLINE_EXCEEDED ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: DEADLINE_EXCEEDED — operation timed out (${cause.message})", cause)
                    else ->
                        PersistentLog.e(this, Constants.logTag, "Firestore: unhandled error ${cause.code} (${cause.message})", cause)
                }
            } else {
                defaultHandler?.uncaughtException(thread, throwable)
            }
        }
    }

    fun configurePipAutoEnter(enabled: Boolean, aspectRatio: Rational?) {
        pipAutoEnterEnabled = enabled
        if (aspectRatio != null) pipAspectRatio = aspectRatio

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val params = PictureInPictureParams.Builder().setAutoEnterEnabled(enabled)
            if (aspectRatio != null) params.setAspectRatio(aspectRatio)
            setPictureInPictureParams(params.build())
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S &&
            pipAutoEnterEnabled &&
            !isInPictureInPictureMode
        ) {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(pipAspectRatio)
                .build()
            enterPictureInPictureMode(params)
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        val wasInPictureInPictureMode = pipModeActive
        pipModeActive = isInPictureInPictureMode
        if (isInPictureInPictureMode) {
            pipExitPending = false
            pipDismissedSent = false
        } else if (wasInPictureInPictureMode && !pipActivityResumed) {
            pipExitPending = true
        } else if (pipActivityResumed) {
            pipExitPending = false
        }
        MethodCallHandler.invokeMethod("pip-mode-changed", mapOf("active" to isInPictureInPictureMode))
    }

    override fun onResume() {
        super.onResume()
        pipExitPending = false
        pipDismissedSent = false
    }

    override fun onStop() {
        if (pipModeActive || isInPictureInPictureMode || pipExitPending) {
            if (!getSystemService(PowerManager::class.java).isInteractive) {
                super.onStop()
                return
            }
            if (pipModeActive || isInPictureInPictureMode) {
                MethodCallHandler.invokeMethod("pip-mode-changed", mapOf("active" to false))
            }
            pipModeActive = false
            pipExitPending = false
            if (!pipDismissedSent) {
                pipDismissedSent = true
                MethodCallHandler.invokeMethod("pip-dismissed", emptyMap())
            }
        }
        super.onStop()
    }

    override fun onDestroy() {
        PersistentLog.d(this, Constants.logTag, "BlueBubbles MainActivity is being destroyed")
        MethodCallHandler.clearNotificationListenerResult()
        MethodCallHandler.clearPickImagesResult()
        setEngine(null, this)

        // If we are finishing "gracefully", the dart code would have started the foreground service.
        // If we are finishing because the system is destroying the activity, we need to start the foreground service
        // via a broadcast intent.
        if (isFinishing) {
            PersistentLog.d(this, Constants.logTag, "BlueBubbles activity is finishing")
        } else {
            PersistentLog.d(this, Constants.logTag, "BlueBubbles activity is being destroyed by the system")

            val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", 0)
            val keepAppAlive: Boolean = prefs.getBoolean("keepAppAlive", false)

            // Create an intent to start the foreground service
            if (keepAppAlive) {
                PersistentLog.d(this, Constants.logTag, "Creating broadcast intent to restart the foreground service...")
                val broadcastIntent = Intent(this, ForegroundServiceBroadcastReceiver::class.java)
                broadcastIntent.setAction("restartservice");
                sendBroadcast(broadcastIntent);
            }
        }

        try {
            super.onDestroy()
        } catch (e: ConcurrentModificationException) {
            PersistentLog.e(this, Constants.logTag, "Caught ConcurrentModificationException when destroying MainActivity", e)
        } catch (e: Exception) {
            PersistentLog.e(this, Constants.logTag, "Caught unhandled Exception when destroying MainActivity", e)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == Constants.notificationListenerRequestCode) {
            MethodCallHandler.consumeNotificationListenerResult()?.success(resultCode == Activity.RESULT_OK)
        } else if (requestCode == Constants.pickImagesRequestCode) {
            PickImagesHandler.onActivityResult(this, resultCode, data)
        }
    }
}