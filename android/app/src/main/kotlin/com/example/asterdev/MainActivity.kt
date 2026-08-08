package com.example.asterdev

import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var walletStorageChannel: MethodChannel? = null
    private var walletStorageExecutor: ExecutorService? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val policy = WalletStoragePolicy(filesDir)
        val executor = Executors.newSingleThreadExecutor { operation ->
            Thread(operation, "utexo-wallet-storage").apply { isDaemon = true }
        }
        walletStorageExecutor = executor
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WalletStoragePolicy.channelName,
        )
        channel.setMethodCallHandler { call, result ->
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
            }
        }
        walletStorageChannel = channel
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        walletStorageChannel?.setMethodCallHandler(null)
        walletStorageChannel = null
        walletStorageExecutor?.shutdown()
        walletStorageExecutor = null
        super.cleanUpFlutterEngine(flutterEngine)
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
            "replaceTextFile" -> {
                val contents = call.argument<String>("contents") ?: fail(PolicyError.argument)
                replaceTextFile(target, contents)
            }
            else -> fail(PolicyError.argument)
        }
    }

    private fun prepareRoot(directory: File) {
        val metadata = metadataOrNull(directory)
        if (metadata == null) {
            requireSecureParent(directory)
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
        requireOwnedDirectory(metadataOrNull(directory) ?: fail(PolicyError.missing))
    }

    private fun verifyFile(file: File) {
        requireOwnedFile(metadataOrNull(file) ?: fail(PolicyError.missing))
    }

    private fun replaceTextFile(file: File, contents: String) {
        val bytes = contents.toByteArray(Charsets.UTF_8)
        if (bytes.isEmpty() || bytes.size > maximumTextFileBytes) {
            fail(PolicyError.argument)
        }
        val parent = requireSecureParent(file)
        metadataOrNull(file)?.let(::requireOwnedFile)
        val temporary = File.createTempFile(".utexo-", ".tmp", parent)
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
        val metadata = metadataOrNull(canonicalParent) ?: fail(PolicyError.parent)
        try {
            if (canonicalParent == root) {
                requireOwnedDirectoryIdentity(metadata)
            } else {
                requireOwnedDirectory(metadata)
            }
        } catch (_: WalletStoragePolicyException) {
            fail(PolicyError.parent)
        }
        return parent
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

    private fun requireOwnedDirectoryIdentity(metadata: DirectoryMetadata) {
        if (!metadata.isDirectory || metadata.ownerId != Os.geteuid()) {
            fail(PolicyError.identity)
        }
    }

    private fun requireOwnedDirectory(metadata: DirectoryMetadata) {
        requireOwnedDirectoryIdentity(metadata)
        if (metadata.permissions != ownerOnlyPermissions) fail(PolicyError.permissions)
    }

    private fun requireOwnedFile(metadata: DirectoryMetadata) {
        if (!metadata.isRegularFile || metadata.ownerId != Os.geteuid()) {
            fail(PolicyError.identity)
        }
        if (metadata.permissions != ownerOnlyFilePermissions) {
            fail(PolicyError.permissions)
        }
    }

    private fun metadataOrNull(file: File): DirectoryMetadata? {
        val status = try {
            Os.lstat(file.path)
        } catch (error: ErrnoException) {
            if (error.errno == OsConstants.ENOENT) return null
            throw error
        }
        return DirectoryMetadata(
            isDirectory = status.st_mode and OsConstants.S_IFMT == OsConstants.S_IFDIR,
            isRegularFile = status.st_mode and OsConstants.S_IFMT == OsConstants.S_IFREG,
            ownerId = status.st_uid,
            permissions = status.st_mode and permissionMask,
        )
    }

    private fun fail(reason: PolicyError): Nothing = throw WalletStoragePolicyException(reason)

    private data class DirectoryMetadata(
        val isDirectory: Boolean,
        val isRegularFile: Boolean,
        val ownerId: Int,
        val permissions: Int,
    )

    companion object {
        const val channelName = "com.utexo.wallet/storage_security"
        private const val ownerOnlyPermissions = 0x1C0
        private const val ownerOnlyFilePermissions = 0x180
        private const val permissionMask = 0x1FF
        private const val maximumTextFileBytes = 1024 * 1024
    }
}

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
