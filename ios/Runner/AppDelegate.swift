import Flutter
import Darwin
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var walletStorageChannel: FlutterMethodChannel?
  private var walletStorageSession: StorageChannelSession?
  private let walletStorageQueue = DispatchQueue(
    label: "com.utexo.wallet.storage-security",
    qos: .utility
  )

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    walletStorageSession?.invalidate()
    walletStorageChannel?.setMethodCallHandler(nil)
    let channel = FlutterMethodChannel(
      name: WalletStoragePolicy.channelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    let queue = walletStorageQueue
    let session = StorageChannelSession()
    channel.setMethodCallHandler { call, result in
      guard session.tryBegin() else {
        result(
          FlutterError(
            code: "wallet_storage_unavailable",
            message: "Wallet storage policy failed.",
            details: nil
          )
        )
        return
      }
      queue.async {
        let response: FlutterError?
        do {
          try WalletStoragePolicy.handle(call)
          response = nil
        } catch {
          response = FlutterError(
            code: "wallet_storage_\(WalletStoragePolicy.diagnosticCode(error))",
            message: "Wallet storage policy failed.",
            details: nil
          )
        }
        DispatchQueue.main.async {
          if session.complete() {
            result(response)
          }
        }
      }
    }
    walletStorageChannel = channel
    walletStorageSession = session
  }
}

final class StorageChannelSession {
  private let lock = NSLock()
  private var active = true
  private var pending = false

  func tryBegin() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard active, !pending else { return false }
    pending = true
    return true
  }

  func complete() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard active, pending else { return false }
    pending = false
    return true
  }

  func invalidate() {
    lock.lock()
    defer { lock.unlock() }
    active = false
    pending = false
  }
}

enum WalletStoragePolicy {
  static let channelName = "com.utexo.wallet/storage_security"
  private static let ownerOnlyPermissions: mode_t = 0o700

  static func handle(_ call: FlutterMethodCall) throws {
    guard
      let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String
    else {
      throw PolicyError.argument
    }
    let url = try validatedURL(path)
    switch call.method {
    case "prepareRoot":
      try prepareRoot(url)
    case "createDirectory":
      try createDirectory(url)
    case "verifyDirectory":
      try verifyDirectory(url)
    case "verifyFile":
      try verifyFile(url)
    case "replaceTextFile":
      guard let contents = arguments["contents"] as? String else {
        throw PolicyError.argument
      }
      try replaceTextFile(url, contents: contents)
    default:
      throw PolicyError.argument
    }
  }

  static func diagnosticCode(_ error: Error) -> String {
    (error as? PolicyError)?.rawValue ?? "native"
  }

  private static func prepareRoot(_ url: URL) throws {
    try ensureApplicationSupportRoot()
    try requireSecureParent(url)
    var metadata = stat()
    if lstat(url.path, &metadata) == 0 {
      try requireOwnedDirectoryIdentity(metadata)
      guard chmod(url.path, ownerOnlyPermissions) == 0 else {
        throw PolicyError.permissions
      }
    } else {
      guard errno == ENOENT else { throw PolicyError.native }
      try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: NSNumber(value: ownerOnlyPermissions)]
      )
    }
    try applyProtection(url)
    try verifyDirectory(url)
  }

  private static func createDirectory(_ url: URL) throws {
    var metadata = stat()
    if lstat(url.path, &metadata) == 0 { throw PolicyError.collision }
    guard errno == ENOENT else { throw PolicyError.native }
    try requireSecureParent(url)
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: NSNumber(value: ownerOnlyPermissions)]
    )
    do {
      try applyProtection(url)
      try verifyDirectory(url)
    } catch {
      let creationError = error
      guard rmdir(url.path) == 0 else { throw PolicyError.native }
      throw creationError
    }
  }

  private static func verifyDirectory(_ url: URL) throws {
    try requireSecureParent(url)
    var metadata = stat()
    guard lstat(url.path, &metadata) == 0 else { throw PolicyError.missing }
    try requireOwnedDirectory(metadata)
    let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
    guard values.isExcludedFromBackup == true else { throw PolicyError.backup }
#if !targetEnvironment(simulator)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard
      let protection = attributes[.protectionKey] as? FileProtectionType,
      protection == .complete
    else {
      throw PolicyError.protection
    }
#endif
  }

  private static func verifyFile(_ url: URL) throws {
    try requireSecureParent(url)
    var metadata = stat()
    guard lstat(url.path, &metadata) == 0 else { throw PolicyError.missing }
    try requireOwnedFile(metadata)
    let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
    guard values.isExcludedFromBackup == true else { throw PolicyError.backup }
#if !targetEnvironment(simulator)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard
      let protection = attributes[.protectionKey] as? FileProtectionType,
      protection == .complete
    else {
      throw PolicyError.protection
    }
#endif
  }

  private static func replaceTextFile(_ url: URL, contents: String) throws {
    guard
      let data = contents.data(using: .utf8),
      !data.isEmpty,
      data.count <= 1_048_576
    else {
      throw PolicyError.argument
    }
    try requireSecureParent(url)
    var existing = stat()
    if lstat(url.path, &existing) == 0 {
      try requireOwnedFile(existing)
    } else if errno != ENOENT {
      throw PolicyError.native
    }

    let temporary = url.deletingLastPathComponent().appendingPathComponent(
      ".utexo-\(UUID().uuidString).tmp",
      isDirectory: false
    )
    var descriptor = open(
      temporary.path,
      O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
      0o600
    )
    guard descriptor >= 0 else { throw PolicyError.native }
    var renamed = false
    defer {
      if descriptor >= 0 { _ = close(descriptor) }
      if !renamed { _ = unlink(temporary.path) }
    }

    try data.withUnsafeBytes { rawBuffer in
      guard let start = rawBuffer.baseAddress else { throw PolicyError.native }
      var offset = 0
      while offset < rawBuffer.count {
        let written = Darwin.write(
          descriptor,
          start.advanced(by: offset),
          rawBuffer.count - offset
        )
        if written < 0 {
          if errno == EINTR { continue }
          throw PolicyError.native
        }
        guard written > 0 else { throw PolicyError.native }
        offset += written
      }
    }
    guard fchmod(descriptor, 0o600) == 0 else { throw PolicyError.permissions }
    try applyProtection(temporary)
    guard fsync(descriptor) == 0 else { throw PolicyError.native }
    guard close(descriptor) == 0 else { throw PolicyError.native }
    descriptor = -1
    guard Darwin.rename(temporary.path, url.path) == 0 else {
      throw PolicyError.native
    }
    renamed = true
    try syncDirectory(url.deletingLastPathComponent())
    try verifyFile(url)
  }

  private static func syncDirectory(_ url: URL) throws {
    let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard descriptor >= 0 else { throw PolicyError.native }
    guard fsync(descriptor) == 0 else {
      _ = close(descriptor)
      throw PolicyError.native
    }
    guard close(descriptor) == 0 else { throw PolicyError.native }
  }

  private static func applyProtection(_ url: URL) throws {
    try FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: url.path
    )
    var protectedURL = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try protectedURL.setResourceValues(values)
  }

  private static func requireSecureParent(_ url: URL) throws {
    let root = try applicationSupportRoot()
    var current = url.deletingLastPathComponent().standardizedFileURL
    while true {
      var metadata = stat()
      guard lstat(current.path, &metadata) == 0 else {
        throw PolicyError.parent
      }
      do {
        if current.path == root.path {
          try requireOwnedDirectoryIdentity(metadata)
        } else {
          try requireOwnedDirectory(metadata)
        }
      } catch {
        throw PolicyError.parent
      }
      if current.path == root.path { break }
      let ancestor = current.deletingLastPathComponent().standardizedFileURL
      guard ancestor.path != current.path else { throw PolicyError.parent }
      current = ancestor
    }
  }

  private static func requireOwnedDirectory(_ metadata: stat) throws {
    try requireOwnedDirectoryIdentity(metadata)
    guard metadata.st_mode & mode_t(0o777) == ownerOnlyPermissions else {
      throw PolicyError.permissions
    }
  }

  private static func requireOwnedDirectoryIdentity(_ metadata: stat) throws {
    guard (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
      metadata.st_uid == geteuid()
    else {
      throw PolicyError.identity
    }
  }

  private static func requireOwnedFile(_ metadata: stat) throws {
    guard (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
      metadata.st_uid == geteuid(),
      metadata.st_nlink == 1
    else {
      throw PolicyError.identity
    }
    guard metadata.st_mode & mode_t(0o777) == mode_t(0o600) else {
      throw PolicyError.permissions
    }
  }

  private static func validatedURL(_ path: String) throws -> URL {
    guard path == path.trimmingCharacters(in: .whitespacesAndNewlines),
      !path.isEmpty,
      (path as NSString).isAbsolutePath,
      !(path as NSString).pathComponents.contains(where: { $0 == "." || $0 == ".." }),
      let support = try? applicationSupportRoot()
    else {
      throw PolicyError.path
    }
    let standardizedSupport = support
    let root = standardizedSupport.path + "/"
    let url = URL(fileURLWithPath: path).standardizedFileURL
    guard url.path.hasPrefix(root) else { throw PolicyError.path }

    let resolvedSupport = standardizedSupport.resolvingSymlinksInPath()
    let resolvedURL = url.resolvingSymlinksInPath()
    let resolvedRoot = resolvedSupport.path + "/"
    guard resolvedURL.path.hasPrefix(resolvedRoot) else { throw PolicyError.path }
    let requestedRelative = String(url.path.dropFirst(root.count))
    let resolvedRelative = String(resolvedURL.path.dropFirst(resolvedRoot.count))
    guard requestedRelative == resolvedRelative else { throw PolicyError.path }
    return url
  }

  private static func applicationSupportRoot() throws -> URL {
    guard
      let support = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw PolicyError.parent
    }
    return support.standardizedFileURL
  }

  private static func ensureApplicationSupportRoot() throws {
    let root = try applicationSupportRoot()
    var metadata = stat()
    if lstat(root.path, &metadata) == 0 {
      try requireOwnedDirectoryIdentity(metadata)
      return
    }
    guard errno == ENOENT else { throw PolicyError.native }

    let parent = root.deletingLastPathComponent().standardizedFileURL
    guard lstat(parent.path, &metadata) == 0 else { throw PolicyError.parent }
    do {
      try requireOwnedDirectoryIdentity(metadata)
    } catch {
      throw PolicyError.parent
    }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: NSNumber(value: ownerOnlyPermissions)]
    )
  }

  private enum PolicyError: String, Error {
    case argument
    case backup
    case collision
    case identity
    case missing
    case native
    case parent
    case path
    case permissions
    case protection
  }
}
