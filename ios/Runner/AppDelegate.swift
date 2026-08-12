import Flutter
import Darwin
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var walletStorageChannel: FlutterMethodChannel?
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
    let channel = FlutterMethodChannel(
      name: WalletStoragePolicy.channelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      walletStorageQueue.async {
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
          result(response)
        }
      }
    }
    walletStorageChannel = channel
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
      throw PolicyError.path
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
        throw PolicyError.path
      }
      try replaceTextFile(url, contents: contents)
    default:
      throw PolicyError.path
    }
  }

  static func diagnosticCode(_ error: Error) -> String {
    (error as? PolicyError)?.rawValue ?? "native"
  }

  private static func prepareRoot(_ url: URL) throws {
    var metadata = stat()
    if lstat(url.path, &metadata) == 0 {
      try requireOwnedDirectoryIdentity(metadata)
      guard chmod(url.path, ownerOnlyPermissions) == 0 else {
        throw PolicyError.permissions
      }
    } else {
      guard errno == ENOENT else { throw PolicyError.native }
      try requireSecureParent(url)
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
    guard lstat(url.path, &metadata) != 0, errno == ENOENT else {
      throw PolicyError.collision
    }
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
      throw PolicyError.path
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
    defer { _ = close(descriptor) }
    guard fsync(descriptor) == 0 else { throw PolicyError.native }
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
    let parent = url.deletingLastPathComponent()
    var metadata = stat()
    guard lstat(parent.path, &metadata) == 0 else { throw PolicyError.parent }
    do {
      if try isApplicationSupportRoot(parent) {
        try requireOwnedDirectoryIdentity(metadata)
      } else {
        try requireOwnedDirectory(metadata)
      }
    } catch {
      throw PolicyError.parent
    }
  }

  private static func isApplicationSupportRoot(_ url: URL) throws -> Bool {
    guard
      let support = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw PolicyError.parent
    }
    return url.standardizedFileURL.path == support.standardizedFileURL.path
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
      metadata.st_uid == geteuid()
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
      let support = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw PolicyError.path
    }
    let standardizedSupport = support.standardizedFileURL
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

  private enum PolicyError: String, Error {
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
