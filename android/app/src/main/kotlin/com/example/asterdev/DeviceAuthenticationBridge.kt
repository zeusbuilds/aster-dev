package com.example.asterdev

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Shader
import android.hardware.biometrics.BiometricManager.Authenticators
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import kotlin.math.ceil
import kotlin.math.roundToInt

/** Device credentials never cross this channel; only bounded outcomes do. */
internal class DeviceAuthenticationBridge(private val activity: Activity) {
    private var channel: MethodChannel? = null
    private var pending: MethodChannel.Result? = null
    private var cancellation: CancellationSignal? = null
    private var generation = 0L
    private var legacyCredentialPending = false
    private var hostResumed = false
    private var sensitive = false
    private var authenticationSnapshotProtection = false
    private var authenticationPresentationFinished = true
    private var privacyCover: WalletPrivacyView? = null

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
                "finishAuthenticationPresentation" -> {
                    if (pending != null) {
                        fail(result, "busy")
                    } else {
                        authenticationPresentationFinished = true
                        finishSnapshotProtectionIfForeground()
                        result.success(null)
                    }
                }
                "setSensitive" -> {
                    val sensitive = call.argument<Boolean>("sensitive")
                    if (sensitive == null) {
                        fail(result, "argument")
                    } else {
                        this.sensitive = sensitive
                        updateSnapshotProtection()
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
        // The legacy credential Activity intentionally stops this host. Keep
        // its task snapshot private without placing a branded page over the
        // source screen. This protection outlives the result until onResume.
        authenticationSnapshotProtection = true
        authenticationPresentationFinished = false
        updateSnapshotProtection()
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
        finishSnapshotProtectionIfForeground()
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
        finishSnapshotProtectionIfForeground()
        return result
    }

    fun cancel() {
        authenticationPresentationFinished = true
        if (legacyCredentialPending) {
            // Keep this marker until its result, preventing a second credential
            // activity while the first is still being dismissed by Android.
            @Suppress("DEPRECATION")
            activity.finishActivity(credentialRequestCode)
        }
        complete("cancelled")
    }

    fun onHostPaused() {
        hostResumed = false
        // Keep the source below an owned OS prompt, including vendor prompt
        // implementations that briefly pause their host. FLAG_SECURE protects
        // its task snapshot throughout this interval. A non-legacy onStop or
        // any user-leave signal still covers and revokes immediately.
        if (!authenticationSnapshotProtection || authenticationPresentationFinished) {
            coverForBackground()
        }
    }

    private fun coverForBackground() {
        if (privacyCover != null) return
        val decor = activity.window.decorView as? ViewGroup ?: return
        privacyCover = WalletPrivacyView(activity).apply {
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
        coverForBackground()
        channel?.invokeMethod("backgrounded", null)
        cancel()
    }

    fun onUserLeaveHint() {
        // Our legacy credential Intent suppresses this callback. Home/Recents
        // initiated by the user must revoke authentication immediately.
        coverForBackground()
        channel?.invokeMethod("backgrounded", null)
        cancel()
    }

    fun uncoverOnResume() {
        hostResumed = true
        // An actual background event already revoked Flutter access. Its gate
        // remains locked when the snapshot cover is removed; an owned system
        // credential return may simply reveal the unchanged source screen.
        privacyCover?.let { (it.parent as? ViewGroup)?.removeView(it) }
        privacyCover = null
        finishSnapshotProtectionIfForeground()
    }

    private fun finishSnapshotProtectionIfForeground() {
        if (hostResumed && authenticationPresentationFinished &&
            pending == null && !legacyCredentialPending
        ) {
            authenticationSnapshotProtection = false
            updateSnapshotProtection()
        }
    }

    private fun updateSnapshotProtection() {
        if (sensitive || authenticationSnapshotProtection) {
            activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
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

/** Independent of user-owned launch/icon resources and all wallet content. */
private class WalletPrivacyView(context: Context) : View(context) {
    private val density = resources.displayMetrics.density
    private val artworkScale = 160f * density / 705f
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private var mark: Bitmap? = null

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        // Always draw the complete opaque background, including while its
        // render is interrupted by system UI.
        canvas.drawColor(Color.WHITE)
        val image = mark ?: renderMark().also { mark = it }
        // Centre the visible mark, rather than the asymmetric Figma filter
        // canvas (20 above / 40 below in source units).
        canvas.drawBitmap(
            image, (width - 160f * density) / 2f - 30f * artworkScale,
            (height - 373f * artworkScale) / 2f - 20f * artworkScale, paint,
        )
    }

    private fun renderMark(): Bitmap {
        val leftPadding = 30f * artworkScale
        val topPadding = 20f * artworkScale
        val logoHeight = 373f * artworkScale
        // Preserve the supplied export's exact filter extent, not an
        // unbounded logical-pixel drop shadow.
        val image = Bitmap.createBitmap(
            ceil(765f * artworkScale).toInt(),
            ceil(433f * artworkScale).toInt(),
            Bitmap.Config.ARGB_8888,
        )
        // A small bitmap Canvas supplies software mask blurs without forcing
        // the full-screen privacy cover into a software-rendered layer.
        val canvas = Canvas(image)
        val source = logoPath(artworkScale, leftPadding, topPadding)
        val markPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        fun gradient(first: Int, last: Int) = LinearGradient(
            0f, topPadding, 0f, topPadding + logoHeight,
            intArrayOf(first, last), floatArrayOf(0.346154f, 1f), Shader.TileMode.CLAMP,
        )
        markPaint.shader = gradient(Color.rgb(0, 26, 255), Color.argb(77, 0, 26, 255))
        canvas.drawPath(source, markPaint)

        val output = Bitmap.createBitmap(image.width, image.height, Bitmap.Config.ARGB_8888)
        val compositor = Canvas(output)
        // Figma saturates SourceAlpha × 127 before blurring and cuts the
        // original silhouette out of each shadow. Preserve that exported
        // behaviour, including anti-aliased edge alpha.
        val pixels = IntArray(image.width * image.height)
        image.getPixels(pixels, 0, image.width, 0, 0, image.width, image.height)
        for (index in pixels.indices) {
            pixels[index] = Color.argb(minOf(255, Color.alpha(pixels[index]) * 127), 0, 0, 0)
        }
        val hardAlpha = Bitmap.createBitmap(pixels, image.width, image.height, Bitmap.Config.ARGB_8888)
        fun shadow(opacity: Float, offset: Float, sigma: Float) {
            // Android BlurMaskFilter accepts a radius and converts it to
            // sigma internally; invert its documented native conversion.
            val radius = (sigma * artworkScale - 0.5f) / 0.57735f
            val alphaPaint = Paint().apply {
                maskFilter = BlurMaskFilter(radius, BlurMaskFilter.Blur.NORMAL)
            }
            val position = IntArray(2)
            val alpha = hardAlpha.extractAlpha(alphaPaint, position)
            val outside = Bitmap.createBitmap(image.width, image.height, Bitmap.Config.ARGB_8888)
            val shadowCanvas = Canvas(outside)
            shadowCanvas.drawBitmap(
                alpha, position[0].toFloat(), position[1] + offset * artworkScale,
                Paint().apply { color = Color.BLACK },
            )
            shadowCanvas.drawBitmap(hardAlpha, 0f, 0f, Paint().apply {
                xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_OUT)
            })
            compositor.drawBitmap(outside, 0f, 0f, Paint().apply {
                this.alpha = (255f * opacity).roundToInt()
            })
            outside.recycle()
            alpha.recycle()
        }
        // Blur and offsets remain in authored source units on every platform.
        shadow(0.1f, 2f, 3f)
        shadow(0.06f, 10f, 15f)
        compositor.drawBitmap(image, 0f, 0f, null)
        hardAlpha.recycle()
        image.recycle()
        return output
    }

    private fun logoPath(scale: Float, leftPadding: Float, topPadding: Float): Path {
        // Exact merged outline from assets/brand/aster-mark.svg.
        val vertices = floatArrayOf(
            539.285f, 28.6915f, 401.285f, 166.366f, 705f, 166.366f, 705f, 206.944f,
            401.596f, 206.944f, 539.285f, 344.308f, 510.526f, 373f, 352.343f, 215.19f,
            194.163f, 373f, 165.403f, 344.308f, 303.093f, 206.944f, 151.546f, 206.944f,
            0f, 206.944f, 0f, 166.366f, 303.404f, 166.366f, 165.403f, 28.6915f,
            194.165f, 0f, 352.343f, 157.807f, 510.526f, 0f,
        )
        return Path().apply {
            moveTo(vertices[0] * scale + leftPadding, vertices[1] * scale + topPadding)
            for (index in 2 until vertices.size step 2) {
                lineTo(vertices[index] * scale + leftPadding, vertices[index + 1] * scale + topPadding)
            }
            close()
        }
    }
}
