package com.example.asterdev

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.hardware.biometrics.BiometricManager.Authenticators
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor

/** Device credentials never cross this channel; only bounded outcomes do. */
internal class DeviceAuthenticationBridge(private val activity: Activity) {
    private var channel: MethodChannel? = null
    private var pending: MethodChannel.Result? = null
    private var cancellation: CancellationSignal? = null
    private var generation = 0L
    private var legacyCredentialPending = false
    private var privacyCover: View? = null

    fun configure(messenger: BinaryMessenger) {
        detach()
        channel = MethodChannel(messenger, channelName).also {
            it.setMethodCallHandler(::handle)
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getStatus" -> result.success(
                    mapOf("secured" to isDeviceSecured(), "captured" to false),
                )
                "authenticate" -> {
                    val reason = call.argument<String>("reason")
                    if (reason.isNullOrBlank() || reason.length > 160) {
                        fail(result, "argument")
                    } else {
                        authenticate(reason, result)
                    }
                }
                "cancel" -> {
                    cancel()
                    result.success(null)
                }
                "setSensitive" -> {
                    val sensitive = call.argument<Boolean>("sensitive")
                    if (sensitive == null) {
                        fail(result, "argument")
                    } else {
                        if (sensitive) {
                            activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        } catch (_: RuntimeException) {
            fail(result, "unavailable")
        }
    }

    private fun keyguard(): KeyguardManager =
        activity.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            ?: throw IllegalStateException("Device security is unavailable.")

    private fun isDeviceSecured(): Boolean = keyguard().isDeviceSecure

    private fun authenticate(reason: String, result: MethodChannel.Result) {
        if (pending != null || legacyCredentialPending) {
            fail(result, "busy")
            return
        }
        if (!isDeviceSecured()) {
            result.success("unsecured")
            return
        }
        if (activity.isFinishing || activity.isDestroyed || !activity.hasWindowFocus()) {
            fail(result, "not_active")
            return
        }
        pending = result
        val requestGeneration = ++generation
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val signal = CancellationSignal()
                cancellation = signal
                val prompt = BiometricPrompt.Builder(activity)
                    .setTitle("Aster")
                    .setSubtitle(reason)
                    .setAllowedAuthenticators(
                        Authenticators.BIOMETRIC_STRONG or Authenticators.DEVICE_CREDENTIAL,
                    )
                    .build()
                prompt.authenticate(
                    signal,
                    Executor { activity.runOnUiThread(it) },
                    object : BiometricPrompt.AuthenticationCallback() {
                        override fun onAuthenticationSucceeded(
                            result: BiometricPrompt.AuthenticationResult,
                        ) {
                            if (generation == requestGeneration) complete("authenticated")
                        }

                        override fun onAuthenticationError(code: Int, message: CharSequence) {
                            if (generation != requestGeneration) return
                            when (code) {
                                BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED,
                                BiometricPrompt.BIOMETRIC_ERROR_CANCELED,
                                -> complete("cancelled")
                                BiometricPrompt.BIOMETRIC_ERROR_NO_DEVICE_CREDENTIAL -> {
                                    // A race with device-security removal must be checked
                                    // authoritatively, never inferred from biometric state.
                                    try {
                                        if (!isDeviceSecured()) complete("unsecured")
                                        else completeFailure("unavailable")
                                    } catch (_: RuntimeException) {
                                        completeFailure("unavailable")
                                    }
                                }
                                BiometricPrompt.BIOMETRIC_ERROR_LOCKOUT,
                                BiometricPrompt.BIOMETRIC_ERROR_LOCKOUT_PERMANENT,
                                -> completeFailure("locked_out")
                                else -> completeFailure("unavailable")
                            }
                        }

                        // Failed biometric samples remain owned by the OS prompt.
                        // No application retry or failure message is emitted here.
                    },
                )
            } else {
                // API 24–29 cannot express strong-biometric OR credential safely
                // through the platform prompt. Use the system credential flow.
                @Suppress("DEPRECATION")
                val intent = keyguard().createConfirmDeviceCredentialIntent("Aster", reason)
                if (intent == null) {
                    if (!isDeviceSecured()) complete("unsecured")
                    else completeFailure("unavailable")
                    return
                }
                legacyCredentialPending = true
                intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NO_USER_ACTION)
                @Suppress("DEPRECATION")
                activity.startActivityForResult(intent, credentialRequestCode)
            }
        } catch (_: RuntimeException) {
            legacyCredentialPending = false
            completeFailure("unavailable")
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != credentialRequestCode) return false
        legacyCredentialPending = false
        if (pending != null) {
            complete(if (resultCode == Activity.RESULT_OK) "authenticated" else "cancelled")
        }
        return true
    }

    private fun complete(outcome: String) {
        val result = takePending()
        result?.success(outcome)
    }

    private fun completeFailure(code: String) {
        val result = takePending()
        if (result != null) fail(result, code)
    }

    private fun takePending(): MethodChannel.Result? {
        val result = pending
        pending = null
        generation += 1
        val signal = cancellation
        cancellation = null
        signal?.cancel()
        return result
    }

    fun cancel() {
        if (legacyCredentialPending) {
            // Keep this marker until its result, preventing a second credential
            // activity while the first is still being dismissed by Android.
            @Suppress("DEPRECATION")
            activity.finishActivity(credentialRequestCode)
        }
        complete("cancelled")
    }

    fun coverForBackground() {
        if (privacyCover != null) return
        val decor = activity.window.decorView as? ViewGroup ?: return
        privacyCover = FrameLayout(activity).apply {
            setBackgroundResource(com.example.asterdev.R.drawable.aster_privacy_background)
            isClickable = true
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            decor.addView(
                this,
                ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
        }
    }

    fun onHostStopped() {
        // The API24–29 credential Activity is deliberately owned by this auth
        // request. Modern BiometricPrompt is System UI and does not stop the
        // host Activity; a stopped host is therefore a genuine background.
        if (legacyCredentialPending) return
        channel?.invokeMethod("backgrounded", null)
        cancel()
    }

    fun onUserLeaveHint() {
        // Our legacy credential Intent suppresses this callback. Home/Recents
        // initiated by the user must revoke authentication immediately.
        channel?.invokeMethod("backgrounded", null)
        cancel()
    }

    fun uncoverOnResume() {
        // Flutter's lifecycle gate is already opaque on pause. This native cover
        // additionally protects task snapshots before Flutter can render a frame.
        privacyCover?.let { (it.parent as? ViewGroup)?.removeView(it) }
        privacyCover = null
    }

    fun detach() {
        cancel()
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun fail(result: MethodChannel.Result, code: String) {
        result.error("device_auth_$code", "Device authentication is unavailable.", null)
    }

    companion object {
        private const val channelName = "com.aster.wallet/device_authentication"
        private const val credentialRequestCode = 7358
    }
}
