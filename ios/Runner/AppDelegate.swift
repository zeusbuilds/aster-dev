import Flutter
import Darwin
import UIKit
import LocalAuthentication
import CoreImage

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
  private var authenticationPrivacy = ForegroundAuthenticationPrivacy()

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
      case "finishAuthenticationPresentation":
        guard self.pending == nil else {
          result(self.failure("busy"))
          return
        }
        let owner = self.authenticationPrivacy.ownerSceneID
        let active = UIApplication.shared.connectedScenes.contains {
          $0.session.persistentIdentifier == owner && $0.activationState == .foregroundActive
        }
        self.authenticationPrivacy.finishPresentation(sceneIsActive: active)
        self.updateAllPrivacyWindows()
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
    // Bind this exemption to the scene presenting our own OS prompt. Another
    // window becoming inactive must never inherit its privacy exemption.
    guard let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first(where: { $0.activationState == .foregroundActive }) else {
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
    authenticationPrivacy.begin(in: scene.session.persistentIdentifier)
    nextContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) {
      [weak self] success, error in
      DispatchQueue.main.async {
        guard let self, self.requestID == id else { return }
        if success {
          self.completeAuthentication("authenticated", returningFromOwnedPrompt: true)
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
        case .userCancel:
          self.completeAuthentication("cancelled", returningFromOwnedPrompt: true)
        case .systemCancel, .appCancel:
          // Calls, Home/Recents and other interruptions must not inherit the
          // exemption merely because a local authentication request existed.
          self.completeAuthentication("cancelled")
        case .passcodeNotSet:
          self.completeAuthentication("unsecured", returningFromOwnedPrompt: true)
        case .authenticationFailed:
          self.completeAuthentication(self.failure("failed"), returningFromOwnedPrompt: true)
        case .biometryLockout:
          self.completeAuthentication(self.failure("locked_out"), returningFromOwnedPrompt: true)
        default:
          self.completeAuthentication(self.failure("unavailable"))
        }
      }
    }
  }

  private func completeAuthentication(
    _ response: Any,
    returningFromOwnedPrompt: Bool = false
  ) {
    authenticationPrivacy.finish(returningFromOwnedPrompt: returningFromOwnedPrompt)
    let reply = pending
    pending = nil
    requestID = nil
    context?.invalidate()
    context = nil
    updateAllPrivacyWindows()
    reply?(response)
  }

  private func cancelAuthentication() {
    // A result may already have been delivered while UIKit is dismissing the
    // prompt. Cancellation/engine cleanup must revoke that presentation too.
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
      if authenticationPrivacy.revoke(in: id) {
        channel?.invokeMethod("backgrounded", arguments: nil)
        cancelAuthentication()
      }
      privacyWindows.removeValue(forKey: id)?.isHidden = true
      monitoredScenes.remove(id)
      authenticationPrivacy.didDisconnect(in: id)
      refreshCaptureState()
      return
    }
    monitorCapture(scene)
    if name == UIScene.didEnterBackgroundNotification {
      // This notification precedes UIKit's task snapshot. Cover synchronously,
      // even if our prompt was still pending when the user left the app.
      showPrivacyWindow(scene)
      authenticationPrivacy.didEnterBackground(in: id)
      channel?.invokeMethod("backgrounded", arguments: nil)
      cancelAuthentication()
    } else {
      if name == UIScene.didActivateNotification {
        authenticationPrivacy.didActivate(in: id)
      }
      // willDeactivate may arrive before activationState is updated. Supply
      // the event's state rather than briefly uncovering an unknown interruption.
      updatePrivacyWindow(
        scene,
        activationState: name == UIScene.willDeactivateNotification
          ? .foregroundInactive : scene.activationState
      )
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

  private func updatePrivacyWindow(
    _ scene: UIWindowScene,
    activationState: UIScene.ActivationState? = nil
  ) {
    if authenticationPrivacy.shouldCover(
      sceneID: scene.session.persistentIdentifier,
      activationState: activationState ?? scene.activationState,
      sensitive: sensitive,
      captured: scene.traitCollection.sceneCaptureState == .active
    ) {
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

/// An authentication-owned inactive interval is not a background transition.
/// Keep the source page below the system prompt, without granting access until
/// Flutter has independently observed a resumed foreground. Background and
/// capture protection always take precedence, including during prompt dismissal.
struct ForegroundAuthenticationPrivacy {
  private(set) var ownerSceneID: String?
  private var evaluating = false
  private var releaseRequested = false
  private var backgroundScenes = Set<String>()

  mutating func begin(in sceneID: String) {
    ownerSceneID = sceneID
    evaluating = true
    releaseRequested = false
  }

  mutating func finish(returningFromOwnedPrompt: Bool) {
    evaluating = false
    // A result can precede UIKit's last inactive/active notifications. The
    // caller acknowledges resumed foreground before releasing presentation.
    if !returningFromOwnedPrompt {
      ownerSceneID = nil
      releaseRequested = false
    }
  }

  mutating func finishPresentation(sceneIsActive: Bool) {
    guard !evaluating else { return }
    releaseRequested = true
    if sceneIsActive {
      ownerSceneID = nil
    }
  }

  mutating func didActivate(in sceneID: String) {
    backgroundScenes.remove(sceneID)
    if ownerSceneID == sceneID && releaseRequested && !evaluating {
      ownerSceneID = nil
    }
  }

  mutating func didEnterBackground(in sceneID: String) {
    backgroundScenes.insert(sceneID)
    revoke(in: sceneID)
  }

  mutating func didDisconnect(in sceneID: String) {
    backgroundScenes.remove(sceneID)
    revoke(in: sceneID)
  }

  @discardableResult
  mutating func revoke(in sceneID: String) -> Bool {
    guard ownerSceneID == sceneID else { return false }
    ownerSceneID = nil
    evaluating = false
    releaseRequested = false
    return true
  }

  func shouldCover(
    sceneID: String,
    activationState: UIScene.ActivationState,
    sensitive: Bool,
    captured: Bool
  ) -> Bool {
    if backgroundScenes.contains(sceneID) || (sensitive && captured) { return true }
    switch activationState {
    case .foregroundActive:
      return false
    case .foregroundInactive:
      return ownerSceneID != sceneID
    case .background, .unattached:
      return true
    @unknown default:
      return true
    }
  }
}

private final class WalletPrivacyViewController: UIViewController {
  override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

  override func loadView() {
    view = WalletPrivacyView()
  }
}

/// Independent from the user-owned launch storyboard and app-icon artwork.
/// All privacy states share the initial launch artwork. It is rendered once
/// per display scale, never sampled from wallet UI.
final class WalletPrivacyView: UIView {
  private let mark = UIImageView()
  private var renderedScale: CGFloat = 0
  private static let logoWidth: CGFloat = 160
  private static let logoHeight = logoWidth * 373 / 705
  // The supplied Figma export is 765 × 433 with the mark at (30, 20).
  // Preserve its filter clipping and scale effects with the 705-wide artwork.
  private static let artworkScale = logoWidth / 705
  private static let leftPadding = 30 * artworkScale
  private static let topPadding = 20 * artworkScale
  private static let canvasSize = CGSize(width: 765 * artworkScale, height: 433 * artworkScale)
  private static let imageContext = CIContext(options: [.cacheIntermediates: false])

  override init(frame: CGRect = .zero) {
    super.init(frame: frame)
    isOpaque = true
    backgroundColor = .white
    accessibilityElementsHidden = true
    addSubview(mark)
    mark.isAccessibilityElement = false
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

  override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    mark.frame = CGRect(
      x: (bounds.width - Self.logoWidth) / 2 - Self.leftPadding,
      y: (bounds.height - Self.logoHeight) / 2 - Self.topPadding,
      width: Self.canvasSize.width,
      height: Self.canvasSize.height
    )
    CATransaction.commit()
    let scale = max(traitCollection.displayScale, 1)
    if renderedScale != scale {
      mark.image = Self.renderLogo(scale: scale)
      renderedScale = scale
    }
  }

  private static func renderLogo(scale: CGFloat) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.opaque = false
    format.scale = scale
    let source = UIGraphicsImageRenderer(size: canvasSize, format: format).image { renderer in
      let context = renderer.cgContext
      context.saveGState()
      context.translateBy(x: leftPadding, y: topPadding)
      context.scaleBy(x: artworkScale, y: artworkScale)
      context.addPath(logoPath())
      context.clip()
      let blue = UIColor(red: 0, green: 26 / 255, blue: 1, alpha: 1)
      let colors = [blue.cgColor, blue.withAlphaComponent(0.3).cgColor] as CFArray
      let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.346154, 1]
      )!
      context.drawLinearGradient(
        gradient, start: .zero, end: CGPoint(x: 0, y: 373),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
      )
      context.restoreGState()
    }
    guard let original = source.cgImage else { return source }
    let image = CIImage(cgImage: original)
    // Figma's exported filter creates a hard silhouette, then removes the
    // interior from each shadow. A translucent gradient must not show a
    // shadow underneath the logo itself.
    let hardAlpha = image.applyingFilter("CIColorMatrix", parameters: [
      "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
      "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
      "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
      "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 127),
    ]).applyingFilter("CIColorClamp", parameters: [
      "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
      "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
    ])
    func shadow(opacity: CGFloat, offset: CGFloat, sigma: CGFloat) -> CIImage {
      // Core Image uses a bottom-left origin: negative Y moves the shadow down.
      hardAlpha.transformed(by: CGAffineTransform(
        translationX: 0, y: -offset * artworkScale * scale
      )).applyingFilter("CIGaussianBlur", parameters: [
        "inputRadius": sigma * artworkScale * scale,
      ]).applyingFilter("CISourceOutCompositing", parameters: [
        kCIInputBackgroundImageKey: hardAlpha,
      ]).applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity),
      ])
    }
    // Blur 30/6 is sigma 15/3 in source units, matching the supplied SVG.
    let lower = shadow(opacity: 0.06, offset: 10, sigma: 15)
    let upper = shadow(opacity: 0.1, offset: 2, sigma: 3)
    let output = image.composited(over: lower.composited(over: upper))
    guard let rendered = imageContext.createCGImage(output, from: image.extent) else {
      return source
    }
    return UIImage(cgImage: rendered, scale: scale, orientation: .up)
  }

  private static func logoPath() -> CGPath {
    // Exact outline of assets/brand/aster-mark.svg, including export asymmetry.
    let vertices: [CGPoint] = [
      CGPoint(x: 539.285, y: 28.6915), CGPoint(x: 401.285, y: 166.366),
      CGPoint(x: 705, y: 166.366), CGPoint(x: 705, y: 206.944),
      CGPoint(x: 401.596, y: 206.944), CGPoint(x: 539.285, y: 344.308),
      CGPoint(x: 510.526, y: 373), CGPoint(x: 352.343, y: 215.19),
      CGPoint(x: 194.163, y: 373), CGPoint(x: 165.403, y: 344.308),
      CGPoint(x: 303.093, y: 206.944), CGPoint(x: 151.546, y: 206.944),
      CGPoint(x: 0, y: 206.944), CGPoint(x: 0, y: 166.366),
      CGPoint(x: 303.404, y: 166.366), CGPoint(x: 165.403, y: 28.6915),
      CGPoint(x: 194.165, y: 0), CGPoint(x: 352.343, y: 157.807),
      CGPoint(x: 510.526, y: 0),
    ]
    let path = CGMutablePath()
    path.addLines(between: vertices)
    path.closeSubpath()
    return path
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
