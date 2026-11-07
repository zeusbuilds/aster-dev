package com.example.asterdev

import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.os.Bundle
import android.content.pm.PackageManager
import android.content.Intent
import androidx.core.view.WindowCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val deviceAuthentication by lazy { DeviceAuthenticationBridge(this) }
    private val mainHandler = Handler(Looper.getMainLooper())
    private var walletStorageChannel: MethodChannel? = null
    private var walletStorageExecutor: ExecutorService? = null
    private var walletStorageSession: StorageChannelSession? = null
    private var walletStorageGeneration = 0L
    private var localNetworkChannel: MethodChannel? = null
    private var localNetworkRequest: LocalNetworkPermissionRequest? = null
    private var localNetworkTimeout: Runnable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Native and Flutter opening artwork share the full window centre.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // The embedding waits for Flutter's first frame. Remove the native
            // surface then, without Android fading the matching logo twice.
            splashScreen.setOnExitAnimationListener { it.remove() }
        }
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deviceAuthentication.configure(flutterEngine.dartExecutor.binaryMessenger)
        detachWalletStorageChannel()
        val generation = walletStorageGeneration
        val session = StorageChannelSession()
        val policy = WalletStoragePolicy(filesDir)
        val executor = Executors.newSingleThreadExecutor { operation ->
            Thread(operation, "aster-wallet-storage").apply { isDaemon = true }
        }
        walletStorageExecutor = executor
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WalletStoragePolicy.channelName,
        )
        channel.setMethodCallHandler { call, result ->
            if (!session.tryBegin()) {
                deliverStorageResponse(
                    result,
                    StoragePolicyResponse.failure("unavailable"),
                )
                return@setMethodCallHandler
            }
            try {
                executor.execute {
                    val response = try {
                        policy.handle(call)
                        StoragePolicyResponse.success
                    } catch (error: WalletStoragePolicyException) {
                        StoragePolicyResponse.failure(error.reason.wireName)
                    } catch (_: Exception) {
                        StoragePolicyResponse.failure("native")
                    }
                    mainHandler.post {
                        if (session.complete() &&
                            generation == walletStorageGeneration &&
                            channel === walletStorageChannel
                        ) {
                            deliverStorageResponse(result, response)
                        }
                    }
                }
            } catch (_: RejectedExecutionException) {
                if (session.complete() &&
                    generation == walletStorageGeneration &&
                    channel === walletStorageChannel
                ) {
                    deliverStorageResponse(
                        result,
                        StoragePolicyResponse.failure("unavailable"),
                    )
                }
            }
        }
        walletStorageChannel = channel
        walletStorageSession = session
        configureLocalNetworkChannel(flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        deviceAuthentication.detach()
        detachLocalNetworkChannel()
        detachWalletStorageChannel()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onPause() {
        deviceAuthentication.onHostPaused()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        deviceAuthentication.uncoverOnResume()
    }

    override fun onStop() {
        deviceAuthentication.onHostStopped()
        super.onStop()
    }

    override fun onUserLeaveHint() {
        deviceAuthentication.onUserLeaveHint()
        super.onUserLeaveHint()
    }

    @Deprecated("Android retains this callback for system credential fallback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        deviceAuthentication.onActivityResult(requestCode, resultCode)
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun configureLocalNetworkChannel(flutterEngine: FlutterEngine) {
        detachLocalNetworkChannel()
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.aster.wallet/local_network",
        )
        channel.setMethodCallHandler { call, result ->
            if (call.method != "ensureAccess") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (Build.VERSION.SDK_INT < 37 ||
                checkSelfPermission(localNetworkPermission) == PackageManager.PERMISSION_GRANTED
            ) {
                result.success(true)
                return@setMethodCallHandler
            }
            if (isFinishing || isDestroyed || localNetworkRequest != null) {
                localNetworkUnavailable(result)
                return@setMethodCallHandler
            }
            val pending = LocalNetworkPermissionRequest { granted ->
                if (granted == null) localNetworkUnavailable(result) else result.success(granted)
            }
            localNetworkRequest = pending
            val timeout = Runnable {
                // Keep the in-flight marker until Android answers; a timed-out
                // dialog must not allow a second overlapping permission request.
                pending.complete(null)
            }
            localNetworkTimeout = timeout
            mainHandler.postDelayed(timeout, localNetworkTimeoutMillis)
            try {
                requestPermissions(arrayOf(localNetworkPermission), localNetworkRequestCode)
            } catch (_: RuntimeException) {
                mainHandler.removeCallbacks(timeout)
                localNetworkTimeout = null
                localNetworkRequest = null
                pending.complete(null)
            }
        }
        localNetworkChannel = channel
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != localNetworkRequestCode) return
        localNetworkTimeout?.let(mainHandler::removeCallbacks)
        localNetworkTimeout = null
        val pending = localNetworkRequest
        localNetworkRequest = null
        pending?.complete(
            checkSelfPermission(localNetworkPermission) == PackageManager.PERMISSION_GRANTED,
        )
    }

    private fun detachLocalNetworkChannel() {
        localNetworkChannel?.setMethodCallHandler(null)
        localNetworkChannel = null
        localNetworkTimeout?.let(mainHandler::removeCallbacks)
        localNetworkTimeout = null
        localNetworkRequest?.complete(null)
        localNetworkRequest = null
    }

    private fun localNetworkUnavailable(result: MethodChannel.Result) {
        result.error("local_network_unavailable", "Local network permission is unavailable.", null)
    }

    private fun detachWalletStorageChannel() {
        walletStorageGeneration += 1
        walletStorageSession?.invalidate()
        walletStorageSession = null
        walletStorageChannel?.setMethodCallHandler(null)
        walletStorageChannel = null
        walletStorageExecutor?.shutdown()
        walletStorageExecutor = null
    }

    private fun deliverStorageResponse(
        result: MethodChannel.Result,
        response: StoragePolicyResponse,
    ) {
        if (response.reason == null) {
            result.success(null)
        } else {
            result.error(
                "wallet_storage_${response.reason}",
                "Wallet storage policy failed.",
                null,
            )
        }
    }

    companion object {
        private const val localNetworkPermission = "android.permission.ACCESS_LOCAL_NETWORK"
        private const val localNetworkRequestCode = 7357
        private const val localNetworkTimeoutMillis = 90_000L
    }
}

/** Completes each permission result once, including timeout and engine cleanup races. */
internal class LocalNetworkPermissionRequest(respond: (Boolean?) -> Unit) {
    private val pending = AtomicBoolean(true)
    private var responder: ((Boolean?) -> Unit)? = respond

    fun complete(granted: Boolean?) {
        if (!pending.compareAndSet(true, false)) return
        val response = responder
        responder = null
        response?.invoke(granted)
    }
}

internal class StorageChannelSession {
    private val active = AtomicBoolean(true)
    private val pending = AtomicBoolean(false)

    fun tryBegin(): Boolean {
        if (!active.get() || !pending.compareAndSet(false, true)) return false
        if (active.get()) return true
        pending.set(false)
        return false
    }

    fun complete(): Boolean = pending.getAndSet(false) && active.get()

    fun invalidate() {
        active.set(false)
        pending.set(false)
    }
}

private data class StoragePolicyResponse(val reason: String?) {
    companion object {
        val success = StoragePolicyResponse(null)
        fun failure(reason: String) = StoragePolicyResponse(reason)
    }
}

private class WalletStoragePolicy(private val filesRoot: File) {
    fun handle(call: MethodCall) {
        val path = call.argument<String>("path") ?: fail(PolicyError.argument)
        val target = validatePath(path)
        when (call.method) {
            "prepareRoot" -> prepareRoot(target)
            "createDirectory" -> createDirectory(target)
            "verifyDirectory" -> verifyDirectory(target)
            "verifyFile" -> verifyFile(target)
            "flushDirectory" -> {
                verifyDirectory(target)
                syncDirectory(target)
            }
            "replaceTextFile" -> {
                val contents = call.argument<String>("contents") ?: fail(PolicyError.argument)
                replaceTextFile(target, contents)
            }
            else -> fail(PolicyError.argument)
        }
    }

    private fun prepareRoot(directory: File) {
        requireSecureParent(directory)
        val metadata = metadataOrNull(directory)
        if (metadata == null) {
            Os.mkdir(directory.path, ownerOnlyPermissions)
        } else {
            requireOwnedDirectoryIdentity(metadata)
            Os.chmod(directory.path, ownerOnlyPermissions)
        }
        verifyDirectory(directory)
    }

    private fun createDirectory(directory: File) {
        if (metadataOrNull(directory) != null) fail(PolicyError.collision)
        requireSecureParent(directory)
        Os.mkdir(directory.path, ownerOnlyPermissions)
        try {
            Os.chmod(directory.path, ownerOnlyPermissions)
            verifyDirectory(directory)
        } catch (error: Exception) {
            if (!directory.delete()) fail(PolicyError.cleanup)
            throw error
        }
    }

    private fun verifyDirectory(directory: File) {
        requireSecureParent(directory)
        requireOwnedDirectory(metadataOrNull(directory) ?: fail(PolicyError.missing))
    }

    private fun verifyFile(file: File) {
        requireSecureParent(file)
        requireOwnedFile(metadataOrNull(file) ?: fail(PolicyError.missing))
    }

    private fun replaceTextFile(file: File, contents: String) {
        val bytes = contents.toByteArray(Charsets.UTF_8)
        if (bytes.isEmpty() || bytes.size > maximumTextFileBytes) {
            fail(PolicyError.argument)
        }
        val parent = requireSecureParent(file)
        metadataOrNull(file)?.let(::requireOwnedFile)
        val temporary = File.createTempFile(".aster-", ".tmp", parent)
        try {
            Os.chmod(temporary.path, ownerOnlyFilePermissions)
            FileOutputStream(temporary).use { output ->
                output.write(bytes)
                output.flush()
                output.fd.sync()
            }
            requireOwnedFile(metadataOrNull(temporary) ?: fail(PolicyError.missing))
            Os.rename(temporary.path, file.path)
            syncDirectory(parent)
            verifyFile(file)
        } finally {
            if (temporary.exists()) temporary.delete()
        }
    }

    private fun syncDirectory(directory: File) {
        val descriptor = Os.open(
            directory.path,
            OsConstants.O_RDONLY or OsConstants.O_CLOEXEC,
            0,
        )
        try {
            Os.fsync(descriptor)
        } finally {
            Os.close(descriptor)
        }
    }

    private fun requireSecureParent(target: File): File {
        val parent = target.parentFile ?: fail(PolicyError.parent)
        val root = filesRoot.canonicalFile
        val canonicalParent = parent.canonicalFile
        if (canonicalParent != root &&
            !canonicalParent.path.startsWith(root.path + File.separator)
        ) {
            fail(PolicyError.parent)
        }
        var current = canonicalParent
        while (true) {
            val metadata = metadataOrNull(current) ?: fail(PolicyError.parent)
            try {
                if (current == root) {
                    requireOwnedDirectoryIdentity(metadata)
                } else {
                    requireOwnedDirectory(metadata)
                }
            } catch (_: WalletStoragePolicyException) {
                fail(PolicyError.parent)
            }
            if (current == root) break
            current = current.parentFile ?: fail(PolicyError.parent)
        }
        return canonicalParent
    }

    private fun validatePath(path: String): File {
        if (path.isBlank() || path != path.trim()) fail(PolicyError.path)
        val requested = File(path)
        if (!requested.isAbsolute ||
            requested.toPath().any { it.toString() == "." || it.toString() == ".." }
        ) {
            fail(PolicyError.path)
        }
        val normalizedRoot = filesRoot.absoluteFile.normalize()
        val normalized = requested.absoluteFile.normalize()
        if (normalized == normalizedRoot ||
            !normalized.toPath().startsWith(normalizedRoot.toPath())
        ) {
            fail(PolicyError.path)
        }
        val root = filesRoot.canonicalFile
        val canonical = requested.canonicalFile
        if (canonical == root ||
            !canonical.path.startsWith(root.path + File.separator)
        ) {
            fail(PolicyError.path)
        }
        val normalizedRelative = normalizedRoot.toPath().relativize(normalized.toPath())
        val canonicalRelative = root.toPath().relativize(canonical.toPath())
        if (normalizedRelative != canonicalRelative) fail(PolicyError.path)
        return normalized
    }

    private fun requireOwnedDirectoryIdentity(metadata: StorageMetadata) {
        if (!metadata.isDirectory || metadata.ownerId != Os.geteuid()) {
            fail(PolicyError.identity)
        }
    }

    private fun requireOwnedDirectory(metadata: StorageMetadata) {
        requireOwnedDirectoryIdentity(metadata)
        if (metadata.permissions != ownerOnlyPermissions) fail(PolicyError.permissions)
    }

    private fun requireOwnedFile(metadata: StorageMetadata) {
        if (!metadata.hasOwnedRegularFileIdentity(Os.geteuid())) {
            fail(PolicyError.identity)
        }
        if (metadata.permissions != ownerOnlyFilePermissions) {
            fail(PolicyError.permissions)
        }
    }

    private fun metadataOrNull(file: File): StorageMetadata? {
        val status = try {
            Os.lstat(file.path)
        } catch (error: ErrnoException) {
            if (error.errno == OsConstants.ENOENT) return null
            throw error
        }
        return StorageMetadata(
            isDirectory = status.st_mode and OsConstants.S_IFMT == OsConstants.S_IFDIR,
            isRegularFile = status.st_mode and OsConstants.S_IFMT == OsConstants.S_IFREG,
            ownerId = status.st_uid,
            permissions = status.st_mode and permissionMask,
            linkCount = status.st_nlink,
        )
    }

    private fun fail(reason: PolicyError): Nothing = throw WalletStoragePolicyException(reason)

    companion object {
        const val channelName = "com.aster.wallet/storage_security"
        private const val ownerOnlyPermissions = 0x1C0
        private const val ownerOnlyFilePermissions = 0x180
        private const val permissionMask = 0x1FF
        private const val maximumTextFileBytes = 1024 * 1024
    }
}

internal data class StorageMetadata(
    val isDirectory: Boolean,
    val isRegularFile: Boolean,
    val ownerId: Int,
    val permissions: Int,
    val linkCount: Long,
)

internal fun StorageMetadata.hasOwnedRegularFileIdentity(
    expectedOwnerId: Int,
): Boolean = isRegularFile && ownerId == expectedOwnerId && linkCount == 1L

private class WalletStoragePolicyException(
    val reason: PolicyError,
) : IllegalStateException("Wallet storage policy failed.")

private enum class PolicyError(val wireName: String) {
    argument("argument"),
    cleanup("cleanup"),
    collision("collision"),
    identity("identity"),
    missing("missing"),
    parent("parent"),
    path("path"),
    permissions("permissions"),
}
