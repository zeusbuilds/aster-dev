import Flutter
import Darwin
import UIKit
import LocalAuthentication

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var walletStorageChannel: FlutterMethodChannel?
  private var walletStorageSession: StorageChannelSession?
  private let walletStorageQueue = DispatchQueue(
    label: "com.aster.wallet.storage-security",
    qos: .utility
  )

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    DeviceAuthenticationBridge.shared.startPrivacyMonitoring()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    DeviceAuthenticationBridge.shared.configure(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
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

/// The OS owns the credential UI. Only passcodeNotSet is an unsecured device;
/// unavailable biometry and all unknown failures remain failures.
@MainActor final class DeviceAuthenticationBridge: NSObject {
  static let shared = DeviceAuthenticationBridge()
  private var channel: FlutterMethodChannel?
  private var context: LAContext?
  private var pending: FlutterResult?
  private var requestID: UUID?
  private var sensitive = false
  private var captured = false
  private var monitoringPrivacy = false
  private var privacyWindows: [String: UIWindow] = [:]
  private var monitoredScenes = Set<String>()

  private override init() { super.init() }

  func configure(messenger: FlutterBinaryMessenger) {
    cancelAuthentication()
    channel?.setMethodCallHandler(nil)
    let next = FlutterMethodChannel(
      name: "com.aster.wallet/device_authentication",
      binaryMessenger: messenger
    )
    next.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "getStatus":
        do {
          self.refreshCaptureState()
          result(["secured": try self.isDeviceSecured(), "captured": self.captured])
        } catch {
          result(self.failure("unavailable"))
        }
      case "authenticate":
        guard let arguments = call.arguments as? [String: Any],
          let reason = arguments["reason"] as? String,
          !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          reason.count <= 160
        else {
          result(self.failure("argument"))
          return
        }
        self.authenticate(reason: reason, result: result)
      case "cancel":
        self.cancelAuthentication()
        result(nil)
      case "setSensitive":
        guard let arguments = call.arguments as? [String: Any],
          let value = arguments["sensitive"] as? Bool
        else {
          result(self.failure("argument"))
          return
        }
        self.sensitive = value
        self.refreshCaptureState()
        self.updateAllPrivacyWindows()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = next
  }

  private func isDeviceSecured() throws -> Bool {
    let probe = LAContext()
    defer { probe.invalidate() }
    var error: NSError?
    if probe.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
      return true
    }
    if let error, error.domain == LAError.errorDomain,
      error.code == LAError.passcodeNotSet.rawValue {
      return false
    }
    throw AuthenticationFailure.unavailable
  }

  private func authenticate(reason: String, result: @escaping FlutterResult) {
    guard pending == nil else {
      result(failure("busy"))
      return
    }
    do {
      guard try isDeviceSecured() else {
        result("unsecured")
        return
      }
    } catch {
      result(failure("unavailable"))
      return
    }
    guard UIApplication.shared.connectedScenes.contains(where: {
      $0.activationState == .foregroundActive
    }) else {
      result(failure("not_active"))
      return
    }
    let nextContext = LAContext()
    // A new context and zero reuse ensure every disclosure has fresh consent.
    nextContext.touchIDAuthenticationAllowableReuseDuration = 0
    nextContext.localizedCancelTitle = "Cancel"
    let id = UUID()
    context = nextContext
    pending = result
    requestID = id
    nextContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) {
      [weak self] success, error in
      DispatchQueue.main.async {
        guard let self, self.requestID == id else { return }
        if success {
          self.completeAuthentication("authenticated")
          return
        }
        let nativeError = error as NSError?
        guard let nativeError, nativeError.domain == LAError.errorDomain,
          let code = LAError.Code(rawValue: nativeError.code)
        else {
          self.completeAuthentication(self.failure("unavailable"))
          return
        }
        switch code {
        case .userCancel, .systemCancel, .appCancel:
          self.completeAuthentication("cancelled")
        case .passcodeNotSet:
          self.completeAuthentication("unsecured")
        case .authenticationFailed:
          self.completeAuthentication(self.failure("failed"))
        case .biometryLockout:
          self.completeAuthentication(self.failure("locked_out"))
        default:
          self.completeAuthentication(self.failure("unavailable"))
        }
      }
    }
  }

  private func completeAuthentication(_ response: Any) {
    let reply = pending
    pending = nil
    requestID = nil
    context?.invalidate()
    context = nil
    reply?(response)
  }

  private func cancelAuthentication() {
    guard pending != nil else { return }
    completeAuthentication("cancelled")
  }

  private func failure(_ code: String) -> FlutterError {
    FlutterError(
      code: "device_auth_\(code)",
      message: "Device authentication is unavailable.",
      details: nil
    )
  }

  func startPrivacyMonitoring() {
    guard !monitoringPrivacy else { return }
    monitoringPrivacy = true
    let center = NotificationCenter.default
    for name in [UIScene.willConnectNotification, UIScene.didActivateNotification,
                 UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification,
                 UIScene.didDisconnectNotification] {
      center.addObserver(self, selector: #selector(sceneChanged(_:)), name: name, object: nil)
    }
    for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
      monitorCapture(scene)
    }
  }

  @objc private func sceneChanged(_ notification: Notification) {
    guard let scene = notification.object as? UIWindowScene else { return }
    let id = scene.session.persistentIdentifier
    let name = notification.name
    if name == UIScene.didDisconnectNotification {
      privacyWindows.removeValue(forKey: id)?.isHidden = true
      monitoredScenes.remove(id)
      refreshCaptureState()
      return
    }
    monitorCapture(scene)
    if name == UIScene.willDeactivateNotification ||
      name == UIScene.didEnterBackgroundNotification {
      // Synchronous native cover precedes UIKit's app-switcher snapshot.
      // Do not cancel on inactivity: the system auth prompt causes it too.
      showPrivacyWindow(scene)
    } else {
      updatePrivacyWindow(scene)
    }
    if name == UIScene.didEnterBackgroundNotification {
      channel?.invokeMethod("backgrounded", arguments: nil)
      cancelAuthentication()
    }
    refreshCaptureState()
  }

  private func monitorCapture(_ scene: UIWindowScene) {
    guard monitoredScenes.insert(scene.session.persistentIdentifier).inserted else { return }
    scene.registerForTraitChanges([UITraitSceneCaptureState.self]) {
      [weak self] (scene: UIWindowScene, _: UITraitCollection) in
      self?.refreshCaptureState()
      self?.updatePrivacyWindow(scene)
    }
  }

  private func refreshCaptureState() {
    let next = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .contains { $0.traitCollection.sceneCaptureState == .active }
    guard captured != next else { return }
    captured = next
    channel?.invokeMethod("captureChanged", arguments: next)
  }

  private func updateAllPrivacyWindows() {
    for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
      monitorCapture(scene)
      updatePrivacyWindow(scene)
    }
  }

  private func updatePrivacyWindow(_ scene: UIWindowScene) {
    if scene.activationState != .foregroundActive ||
      (sensitive && scene.traitCollection.sceneCaptureState == .active) {
      showPrivacyWindow(scene)
    } else {
      privacyWindows.removeValue(forKey: scene.session.persistentIdentifier)?.isHidden = true
    }
  }

  private func showPrivacyWindow(_ scene: UIWindowScene) {
    let id = scene.session.persistentIdentifier
    guard privacyWindows[id] == nil else { return }
    let window = UIWindow(windowScene: scene)
    window.windowLevel = .alert + 1
    window.rootViewController = WalletPrivacyViewController()
    window.isUserInteractionEnabled = true
    // Never take key-window status from Flutter or the system credential UI.
    privacyWindows[id] = window
    window.isHidden = false
  }

  private enum AuthenticationFailure: Error { case unavailable }
}

private final class WalletPrivacyViewController: UIViewController {
  override func loadView() {
    let root = UIView()
    root.backgroundColor = .black
    let background = UIImageView(image: UIImage(named: "aster-launch-background"))
    background.contentMode = .scaleAspectFill
    background.clipsToBounds = true
    background.translatesAutoresizingMaskIntoConstraints = false
    let mark = UIImageView(image: UIImage(named: "aster-privacy-mark"))
    mark.contentMode = .scaleAspectFit
    mark.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(background)
    root.addSubview(mark)
    NSLayoutConstraint.activate([
      background.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      background.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      background.topAnchor.constraint(equalTo: root.topAnchor),
      background.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      mark.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      mark.centerYAnchor.constraint(equalTo: root.centerYAnchor),
      mark.widthAnchor.constraint(equalToConstant: 160),
      mark.heightAnchor.constraint(equalToConstant: 128),
    ])
    root.accessibilityElementsHidden = true
    view = root
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
  static let channelName = "com.aster.wallet/storage_security"
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
    case "flushDirectory":
      try verifyDirectory(url)
      try syncDirectory(url)
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
      ".aster-\(UUID().uuidString).tmp",
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
