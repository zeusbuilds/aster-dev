import XCTest
import UIKit
@testable import Runner

final class RunnerTests: XCTestCase {

  private var runnerBundle: Bundle {
    Bundle(for: AppDelegate.self)
  }

  private func makeStorageRoot() throws -> URL {
    let support = try XCTUnwrap(
      FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    )
    let root = support.appendingPathComponent(
      "aster-native-test-\(UUID().uuidString)",
      isDirectory: true
    )
    try invokeStorage("prepareRoot", at: root)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: root)
    }
    return root
  }

  private func invokeStorage(
    _ method: String,
    at url: URL,
    contents: String? = nil
  ) throws {
    var arguments: [String: Any] = ["path": url.path]
    if let contents { arguments["contents"] = contents }
    try WalletStoragePolicy.handle(
      FlutterMethodCall(methodName: method, arguments: arguments)
    )
  }

  private func assertStorageFailure(
    _ expectedCode: String,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ operation: () throws -> Void
  ) {
    do {
      try operation()
      XCTFail("Expected storage failure \(expectedCode)", file: file, line: line)
    } catch {
      XCTAssertEqual(
        WalletStoragePolicy.diagnosticCode(error),
        expectedCode,
        file: file,
        line: line
      )
    }
  }

  func testWalletStorageChannelUsesStableProductNamespace() {
    XCTAssertEqual(
      WalletStoragePolicy.channelName,
      "com.aster.wallet/storage_security"
    )
  }

  @MainActor
  func testPrivacyCoverAlwaysUsesOpaqueWhiteAndGradientBlueArtwork() throws {
    let cover = WalletPrivacyView()
    cover.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    cover.layoutIfNeeded()
    XCTAssertTrue(cover.isOpaque)
    XCTAssertTrue(cover.accessibilityElementsHidden)
    let mark = try XCTUnwrap(cover.subviews.first as? UIImageView)
    let originalImage = try XCTUnwrap(mark.image?.cgImage)
    let initial = try privacyPixels(cover)
    XCTAssertEqual(initial.corner, [255, 255, 255, 255])
    XCTAssertEqual(initial.center[3], 255)
    XCTAssertLessThan(initial.center[0], 100)
    XCTAssertGreaterThan(initial.center[2], 245)
    // One diagonal end is fully blue and the other fades over white. Inspect
    // both ends without depending on bitmap-context row orientation.
    XCTAssertLessThan(min(initial.diagonalA[0], initial.diagonalB[0]), 15)
    XCTAssertGreaterThan(max(initial.diagonalA[0], initial.diagonalB[0]), 100)
    XCTAssertGreaterThan(initial.diagonalA[2], 245)
    XCTAssertGreaterThan(initial.diagonalB[2], 245)

    let logoBytes = try rgbaPixels(originalImage)
    var hasOutsideShadow = false
    for index in stride(from: 0, to: logoBytes.count, by: 4) {
      if logoBytes[index] == 0 && logoBytes[index + 1] == 0 &&
        logoBytes[index + 2] == 0 && logoBytes[index + 3] > 0 {
        hasOutsideShadow = true
        break
      }
    }
    XCTAssertTrue(hasOutsideShadow, "The blue mark retains its actual-outline shadows")

    // Repeated layout and background-cover reuse retain the same artwork and
    // cached image. No launch-phase message can switch this cover's colours.
    cover.setNeedsLayout()
    cover.layoutIfNeeded()
    XCTAssertTrue(cover.isOpaque)
    XCTAssertTrue(cover.subviews.first === mark)
    XCTAssertTrue(originalImage === mark.image?.cgImage)
    let reused = try privacyPixels(cover)
    XCTAssertEqual(reused.corner, initial.corner)
    XCTAssertEqual(reused.center, initial.center)
  }

  func testOwnedAuthenticationKeepsOnlyItsSourceSceneVisible() {
    var privacy = ForegroundAuthenticationPrivacy()
    XCTAssertTrue(privacy.shouldCover(
      sceneID: "wallet", activationState: .foregroundInactive, sensitive: false, captured: false
    ))
    privacy.begin(in: "wallet")
    XCTAssertFalse(privacy.shouldCover(
      sceneID: "wallet", activationState: .foregroundInactive, sensitive: false, captured: false
    ))
    XCTAssertTrue(privacy.shouldCover(
      sceneID: "other", activationState: .foregroundInactive, sensitive: false, captured: false
    ))
    for state in [UIScene.ActivationState.background, .unattached] {
      XCTAssertTrue(privacy.shouldCover(
        sceneID: "wallet", activationState: state, sensitive: false, captured: false
      ))
    }
    for state in [UIScene.ActivationState.foregroundActive, .foregroundInactive] {
      XCTAssertTrue(privacy.shouldCover(
        sceneID: "wallet", activationState: state, sensitive: true, captured: true
      ))
    }
  }

  func testAuthenticationCallbackBeforeLateInactivityRetainsPresentationOwnership() {
    var privacy = ForegroundAuthenticationPrivacy()
    privacy.begin(in: "wallet")
    privacy.finish(returningFromOwnedPrompt: true)
    // The native callback may precede Flutter/UIKit's final lifecycle messages.
    XCTAssertFalse(privacy.shouldCover(
      sceneID: "wallet", activationState: .foregroundInactive, sensitive: false, captured: false
    ))
    privacy.didActivate(in: "wallet")
    XCTAssertEqual(privacy.ownerSceneID, "wallet")
    privacy.finishPresentation(sceneIsActive: true)
    XCTAssertNil(privacy.ownerSceneID)
    // A later unrelated inactive interval is protected again.
    XCTAssertTrue(privacy.shouldCover(
      sceneID: "wallet", activationState: .foregroundInactive, sensitive: false, captured: false
    ))
  }

  func testPresentationCleanupDuringPromptDismissalWaitsForActivation() {
    var privacy = ForegroundAuthenticationPrivacy()
    privacy.begin(in: "wallet")
    privacy.finish(returningFromOwnedPrompt: true)
    privacy.finishPresentation(sceneIsActive: false)
    XCTAssertFalse(privacy.shouldCover(
      sceneID: "wallet", activationState: .foregroundInactive, sensitive: false, captured: false
    ))
    privacy.didActivate(in: "other")
    XCTAssertEqual(privacy.ownerSceneID, "wallet")
    privacy.didActivate(in: "wallet")
    XCTAssertNil(privacy.ownerSceneID)
    XCTAssertTrue(privacy.shouldCover(
      sceneID: "wallet", activationState: .foregroundInactive, sensitive: false, captured: false
    ))
  }

  func testUnexpectedAuthenticationInterruptionImmediatelyRestoresPrivacy() {
    var privacy = ForegroundAuthenticationPrivacy()
    privacy.begin(in: "wallet")
    privacy.finish(returningFromOwnedPrompt: false)
    XCTAssertNil(privacy.ownerSceneID)
    XCTAssertTrue(privacy.shouldCover(
      sceneID: "wallet", activationState: .foregroundInactive, sensitive: false, captured: false
    ))
    privacy.finishPresentation(sceneIsActive: false)
    XCTAssertNil(privacy.ownerSceneID)
  }

  func testBackgroundDuringAuthenticationCannotBeUndoneByALateCallback() {
    var privacy = ForegroundAuthenticationPrivacy()
    privacy.begin(in: "wallet")
    privacy.didEnterBackground(in: "wallet")
    XCTAssertNil(privacy.ownerSceneID)
    privacy.finish(returningFromOwnedPrompt: true)
    privacy.finishPresentation(sceneIsActive: true)
    // Keep covering even if UIKit's property lags its background notification.
    XCTAssertTrue(privacy.shouldCover(
      sceneID: "wallet", activationState: .foregroundActive, sensitive: false, captured: false
    ))
    privacy.didActivate(in: "wallet")
    XCTAssertFalse(privacy.shouldCover(
      sceneID: "wallet", activationState: .foregroundActive, sensitive: false, captured: false
    ))
    XCTAssertTrue(privacy.shouldCover(
      sceneID: "wallet", activationState: .foregroundInactive, sensitive: false, captured: false
    ))
  }

  func testAuthenticationPresentationCleanupDoesNotCancelAnEvaluatingRequest() {
    var privacy = ForegroundAuthenticationPrivacy()
    privacy.begin(in: "wallet")
    privacy.finishPresentation(sceneIsActive: true)
    XCTAssertEqual(privacy.ownerSceneID, "wallet")
    privacy.didEnterBackground(in: "other")
    XCTAssertEqual(privacy.ownerSceneID, "wallet")
    privacy.didDisconnect(in: "wallet")
    XCTAssertNil(privacy.ownerSceneID)
    XCTAssertTrue(privacy.shouldCover(
      sceneID: "wallet", activationState: .foregroundInactive, sensitive: false, captured: false
    ))
  }

  @MainActor
  func testCompiledLaunchArtworkPreservesGradientAndOutsideShadowsAtRetinaScales() throws {
    // This exercises UIImage's compiled asset-catalog path, rather than an SVG
    // parser or a duplicate drawing implementation in the test target.
    let canvas = CGSize(width: 192, height: 128)
    let sRGB = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let visibleMarkWidth: CGFloat = 160
    let sourceMark = CGSize(width: 705, height: 373)
    let sourceCanvas = CGSize(width: 765, height: 473)
    let artworkSize = CGSize(
      width: sourceCanvas.width * visibleMarkWidth / sourceMark.width,
      height: sourceCanvas.height * visibleMarkWidth / sourceMark.width
    )
    let artworkRect = CGRect(
      x: (canvas.width - artworkSize.width) / 2,
      y: (canvas.height - artworkSize.height) / 2,
      width: artworkSize.width,
      height: artworkSize.height
    )

    for scale in [CGFloat(2), CGFloat(3)] {
      let traits = UITraitCollection(traitsFrom: [
        UITraitCollection(displayScale: scale),
        UITraitCollection(userInterfaceStyle: .light),
      ])
      let artwork = try XCTUnwrap(UIImage(
        named: "splash_logo", in: runnerBundle, compatibleWith: traits
      ))
      let format = UIGraphicsImageRendererFormat()
      format.scale = scale
      format.opaque = false
      format.preferredRange = .standard
      let rendered = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
        artwork.draw(in: artworkRect)
      }
      let image = try XCTUnwrap(rendered.cgImage)
      let bytes = try rgbaPixels(image, colorSpace: sRGB)
      if let compiledImage = artwork.cgImage {
        let sourceSpace = compiledImage.colorSpace ?? sRGB
        let sourceValues = try rgbaPixels(compiledImage, colorSpace: sourceSpace)
        let convertedValues = try rgbaPixels(compiledImage, colorSpace: sRGB)
        let metadata = XCTAttachment(string: """
          Compiled asset CGImage: \(compiledImage.width)x\(compiledImage.height)
          Source color space: \(String(describing: sourceSpace.name))
          Opaque blue mode in source space: \(launchOpaqueBlueMode(sourceValues))
          Opaque blue mode converted to sRGB: \(launchOpaqueBlueMode(convertedValues))
          Opaque blue mode after UIImage drawing: \(launchOpaqueBlueMode(bytes))
          """
        )
        metadata.name = "native-launch-color-metadata-\(Int(scale))x"
        metadata.lifetime = .keepAlways
        add(metadata)
        let sourceAttachment = XCTAttachment(image: UIImage(cgImage: compiledImage))
        sourceAttachment.name = "native-launch-compiled-source-\(Int(scale))x"
        sourceAttachment.lifetime = .keepAlways
        add(sourceAttachment)
      }
      var blackShadowPixels = 0
      var maximumBlackAlpha: UInt8 = 0
      var blueMinX = image.width
      var blueMaxX = -1
      for y in 0..<image.height {
        for x in 0..<image.width {
          let index = (y * image.width + x) * 4
          let red = bytes[index]
          let green = bytes[index + 1]
          let blue = bytes[index + 2]
          let alpha = bytes[index + 3]
          if red == 0 && green == 0 && blue == 0 && alpha > 0 {
            blackShadowPixels += 1
            maximumBlackAlpha = max(maximumBlackAlpha, alpha)
          }
          if blue >= 32 && alpha >= 32 && red <= 2 {
            blueMinX = min(blueMinX, x)
            blueMaxX = max(blueMaxX, x)
          }
        }
      }
      XCTAssertGreaterThan(blackShadowPixels, 10, "The compiled SVG must retain its outside shadow")
      XCTAssertLessThan(maximumBlackAlpha, 64, "The shadow must remain subtle, without opaque black artefacts")
      XCTAssertGreaterThanOrEqual(blueMaxX, blueMinX)
      XCTAssertEqual(
        CGFloat(blueMaxX - blueMinX + 1) / scale, visibleMarkWidth, accuracy: 1
      )

      func sample(_ source: CGPoint) -> [UInt8] {
        let sourceScale = visibleMarkWidth / sourceMark.width
        let point = CGPoint(
          x: (canvas.width - visibleMarkWidth) / 2 + source.x * sourceScale,
          y: (canvas.height - sourceMark.height * sourceScale) / 2 + source.y * sourceScale
        )
        let x = min(image.width - 1, max(0, Int(point.x * scale)))
        let y = min(image.height - 1, max(0, Int(point.y * scale)))
        let index = (y * image.width + x) * 4
        return Array(bytes[index..<(index + 4)])
      }

      // Both points are inside diagonal strokes even if the bitmap context
      // reverses the vertical axis. The two ends must retain their opacity
      // difference and pure blue must not be darkened by an interior shadow.
      let diagonalA = sample(CGPoint(x: 200, y: 35))
      let diagonalB = sample(CGPoint(x: 505, y: 338))
      XCTAssertGreaterThan(max(diagonalA[3], diagonalB[3]), 245)
      XCTAssertLessThan(min(diagonalA[3], diagonalB[3]), 130)
      XCTAssertGreaterThan(min(diagonalA[3], diagonalB[3]), 60)
      for pixel in [diagonalA, diagonalB] {
        XCTAssertEqual(pixel[0], 0)
        XCTAssertEqual(Double(pixel[2]), Double(pixel[3]), accuracy: 3)
        XCTAssertEqual(Double(pixel[1]) * 255 / Double(pixel[3]), 26, accuracy: 2)
      }

      // A united fill has the same gradient in the intersection and in the
      // isolated horizontal stroke; independently translucent strokes would
      // overpaint the centre and increase its alpha.
      let intersection = sample(CGPoint(x: 352.5, y: 186.5))
      let horizontal = sample(CGPoint(x: 70, y: 186.5))
      XCTAssertEqual(Double(intersection[3]), Double(horizontal[3]), accuracy: 3)
      XCTAssertEqual(Double(intersection[2]), Double(horizontal[2]), accuracy: 3)
      let attachment = XCTAttachment(image: rendered)
      attachment.name = "native-launch-artwork-\(Int(scale))x"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }

  @MainActor
  func testLaunchStoryboardCentresTheFirstFrameAcrossPhoneSizes() throws {
    let storyboard = UIStoryboard(name: "Launch Screen", bundle: runnerBundle)
    let controller = try XCTUnwrap(storyboard.instantiateInitialViewController())
    let view = try XCTUnwrap(controller.view)
    let images = launchImageViews(in: view)
    XCTAssertEqual(images.count, 1)
    let mark = try XCTUnwrap(images.first)
    XCTAssertEqual(mark.contentMode, .scaleAspectFit)
    XCTAssertNotNil(mark.image)
    let visibleMarkWidth: CGFloat = 160
    let artworkWidth = visibleMarkWidth * 765 / 705
    let artworkHeight = visibleMarkWidth * 473 / 705
    let sRGB = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let widthConstraint = try XCTUnwrap(mark.constraints.first {
      $0.firstAttribute == .width && $0.secondItem == nil && $0.relation == .equal
    })
    let heightConstraint = try XCTUnwrap(mark.constraints.first {
      $0.firstAttribute == .height && $0.secondItem == nil && $0.relation == .equal
    })
    XCTAssertEqual(widthConstraint.constant, artworkWidth, accuracy: 0.000001)
    XCTAssertEqual(heightConstraint.constant, artworkHeight, accuracy: 0.000001)
    XCTAssertEqual(widthConstraint.priority, .required)
    XCTAssertEqual(heightConstraint.priority, .required)
    XCTAssertFalse(mark.translatesAutoresizingMaskIntoConstraints)

    // Reuse the same view hierarchy through resizes: a fixed design-canvas
    // frame can pass one screenshot yet jump on another phone or scene size.
    for size in [
      CGSize(width: 390, height: 844),
      CGSize(width: 402, height: 874),
      CGSize(width: 440, height: 956),
    ] {
      view.frame = CGRect(origin: .zero, size: size)
      view.setNeedsLayout()
      view.layoutIfNeeded()
      let frame = mark.convert(mark.bounds, to: view)
      // Auto Layout preserves the exact contract in its constraints, then
      // UIKit aligns the actual view bounds to this display's physical grid.
      let layoutTolerance = 1 / max(view.traitCollection.displayScale, 1)
      XCTAssertEqual(frame.midX, view.bounds.midX, accuracy: 0.01)
      XCTAssertEqual(frame.midY, view.bounds.midY, accuracy: 0.01)
      XCTAssertEqual(frame.width, artworkWidth, accuracy: layoutTolerance)
      XCTAssertEqual(frame.height, artworkHeight, accuracy: layoutTolerance)

      for scale in [CGFloat(2), CGFloat(3)] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        format.preferredRange = .standard
        let snapshot = UIGraphicsImageRenderer(size: size, format: format).image {
          view.layer.render(in: $0.cgContext)
        }
        let image = try XCTUnwrap(snapshot.cgImage)
        let bytes = try rgbaPixels(image, colorSpace: sRGB)
        XCTAssertEqual(Array(bytes.prefix(4)), [255, 255, 255, 255])
        var minX = image.width
        var minY = image.height
        var maxX = -1
        var maxY = -1
        for y in 0..<image.height {
          for x in 0..<image.width {
            let index = (y * image.width + x) * 4
            // Grey shadow pixels never qualify as blue artwork.
            if Int(bytes[index + 2]) - Int(bytes[index]) > 24 {
              minX = min(minX, x)
              minY = min(minY, y)
              maxX = max(maxX, x)
              maxY = max(maxY, y)
            }
          }
        }
        XCTAssertGreaterThanOrEqual(maxX, minX)
        XCTAssertGreaterThanOrEqual(maxY, minY)
        XCTAssertEqual(CGFloat(maxX - minX + 1) / scale, visibleMarkWidth, accuracy: 1)
        XCTAssertEqual(CGFloat(minX + maxX + 1) / (2 * scale), size.width / 2, accuracy: 0.5)
        XCTAssertEqual(CGFloat(minY + maxY + 1) / (2 * scale), size.height / 2, accuracy: 0.5)
        let attachment = XCTAttachment(image: snapshot)
        attachment.name = "native-launch-layout-\(Int(size.width))x\(Int(size.height))-\(Int(scale))x"
        attachment.lifetime = .keepAlways
        add(attachment)
      }
    }
  }

  @MainActor
  private func launchImageViews(in view: UIView) -> [UIImageView] {
    (view as? UIImageView).map { [$0] } ?? view.subviews.flatMap { launchImageViews(in: $0) }
  }

  private func launchOpaqueBlueMode(_ bytes: [UInt8]) -> String {
    var counts: [UInt32: Int] = [:]
    for index in stride(from: 0, to: bytes.count, by: 4) {
      if bytes[index + 3] != 255 || bytes[index + 2] < 240 { continue }
      let packed = UInt32(bytes[index]) << 16 |
        UInt32(bytes[index + 1]) << 8 | UInt32(bytes[index + 2])
      counts[packed, default: 0] += 1
    }
    guard let mode = counts.max(by: { $0.value < $1.value }) else { return "none" }
    return "[\((mode.key >> 16) & 255), \((mode.key >> 8) & 255), \(mode.key & 255), 255]"
  }

  @MainActor
  private func privacyPixels(_ view: UIView) throws -> (
    corner: [UInt8], center: [UInt8], diagonalA: [UInt8], diagonalB: [UInt8]
  ) {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let snapshot = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image {
      view.layer.render(in: $0.cgContext)
    }
    let image = try XCTUnwrap(snapshot.cgImage)
    let bytes = try rgbaPixels(image)
    let width = image.width
    let height = image.height
    let center = ((height / 2) * width + width / 2) * 4
    let diagonalA = ((height / 2 - 36) * width + width / 2 + 36) * 4
    let diagonalB = ((height / 2 + 36) * width + width / 2 + 36) * 4
    XCTAssertTrue(stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 })
    return (
      Array(bytes[0..<4]), Array(bytes[center..<(center + 4)]),
      Array(bytes[diagonalA..<(diagonalA + 4)]), Array(bytes[diagonalB..<(diagonalB + 4)])
    )
  }

  private func rgbaPixels(
    _ image: CGImage, colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
  ) throws -> [UInt8] {
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue |
      CGImageAlphaInfo.premultipliedLast.rawValue
    let context = try XCTUnwrap(CGContext(
      data: &bytes, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo
    ))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return bytes
  }

  func testUnknownNativeErrorMapsToRedactedDiagnosticCode() {
    let error = NSError(
      domain: "sensitive.native.domain",
      code: 42,
      userInfo: [NSLocalizedDescriptionKey: "must not cross the bridge"]
    )

    XCTAssertEqual(WalletStoragePolicy.diagnosticCode(error), "native")
  }

  func testPrivacyManifestDeclaresOnlyApprovedAppReasons() throws {
    let url = try XCTUnwrap(
      runnerBundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
    )
    let data = try Data(contentsOf: url)
    let root = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    )
    let entries = try XCTUnwrap(
      root["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
    )
    var reasonsByCategory: [String: Set<String>] = [:]
    for entry in entries {
      let category = try XCTUnwrap(entry["NSPrivacyAccessedAPIType"] as? String)
      let reasons = try XCTUnwrap(
        entry["NSPrivacyAccessedAPITypeReasons"] as? [String]
      )
      XCTAssertNil(
        reasonsByCategory.updateValue(Set(reasons), forKey: category),
        "Privacy manifest category \(category) is declared more than once"
      )
    }

    XCTAssertEqual(
      reasonsByCategory,
      [
        "NSPrivacyAccessedAPICategoryDiskSpace": ["E174.1"],
        "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
      ]
    )
    XCTAssertEqual(root["NSPrivacyTracking"] as? Bool, false)
  }

  func testInfoPlistAllowsOnlyNarrowLocalNetworkingException() throws {
    let transport = try XCTUnwrap(
      runnerBundle.object(forInfoDictionaryKey: "NSAppTransportSecurity")
        as? [String: Any]
    )

    XCTAssertEqual(transport["NSAllowsLocalNetworking"] as? Bool, true)
    XCTAssertNil(transport["NSAllowsArbitraryLoads"])
    XCTAssertNil(transport["NSAllowsArbitraryLoadsForMedia"])
    XCTAssertNil(transport["NSAllowsArbitraryLoadsInWebContent"])
  }

  func testBuiltMetadataDeclaresOnlyTheSupportedPhoneFamily() {
    XCTAssertEqual(
      runnerBundle.object(forInfoDictionaryKey: "UIDeviceFamily") as? [Int],
      [1]
    )
    XCTAssertNil(
      runnerBundle.object(
        forInfoDictionaryKey: "UISupportedInterfaceOrientations~ipad"
      )
    )
  }

  func testStorageChannelSessionAdmitsOneOperationAndInvalidatesExactlyOnce() {
    let completed = StorageChannelSession()
    XCTAssertTrue(completed.tryBegin())
    XCTAssertFalse(completed.tryBegin())
    XCTAssertTrue(completed.complete())
    XCTAssertFalse(completed.complete())
    XCTAssertTrue(completed.tryBegin())

    completed.invalidate()
    XCTAssertFalse(completed.complete())
    XCTAssertFalse(completed.tryBegin())
  }

  func testWalletStorageRejectsAnInsecureAncestor() throws {
    let root = try makeStorageRoot()
    let loose = root.appendingPathComponent("loose", isDirectory: true)
    let secure = loose.appendingPathComponent("secure", isDirectory: true)
    try FileManager.default.createDirectory(
      at: loose,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: NSNumber(value: 0o700)]
    )
    try FileManager.default.createDirectory(
      at: secure,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: NSNumber(value: 0o700)]
    )
    XCTAssertEqual(chmod(loose.path, 0o777), 0)

    assertStorageFailure("parent") {
      try invokeStorage(
        "createDirectory",
        at: secure.appendingPathComponent("wallet", isDirectory: true)
      )
    }
  }

  func testWalletStorageRejectsMultiplyLinkedMetadata() throws {
    let root = try makeStorageRoot()
    let metadata = root.appendingPathComponent("registry.a.json")
    let alias = root.appendingPathComponent("registry.alias.json")
    try invokeStorage("replaceTextFile", at: metadata, contents: "first")
    XCTAssertEqual(Darwin.link(metadata.path, alias.path), 0)

    assertStorageFailure("identity") {
      try invokeStorage("verifyFile", at: metadata)
    }
    assertStorageFailure("identity") {
      try invokeStorage("verifyFile", at: alias)
    }

    XCTAssertEqual(unlink(alias.path), 0)
    try invokeStorage("verifyFile", at: metadata)
  }

  func testWalletStorageRejectsBoundsAliasesAndCollisionsWithoutMutation() throws {
    let root = try makeStorageRoot()
    let metadata = root.appendingPathComponent("registry.a.json")
    let directory = root.appendingPathComponent("wallet", isDirectory: true)
    try invokeStorage("replaceTextFile", at: metadata, contents: "first")
    try invokeStorage("createDirectory", at: directory)

    assertStorageFailure("argument") {
      try invokeStorage("replaceTextFile", at: metadata, contents: "")
    }
    assertStorageFailure("argument") {
      try invokeStorage(
        "replaceTextFile",
        at: metadata,
        contents: String(repeating: "x", count: 1_048_577)
      )
    }
    assertStorageFailure("collision") {
      try invokeStorage("createDirectory", at: metadata)
    }
    assertStorageFailure("identity") {
      try invokeStorage("replaceTextFile", at: directory, contents: "replacement")
    }

    let alias = root.appendingPathComponent("registry.link.json")
    XCTAssertEqual(symlink(metadata.path, alias.path), 0)
    assertStorageFailure("path") {
      try invokeStorage("verifyFile", at: alias)
    }
    assertStorageFailure("path") {
      try invokeStorage("replaceTextFile", at: alias, contents: "replacement")
    }

    XCTAssertEqual(try String(contentsOf: metadata, encoding: .utf8), "first")
    XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
  }
}
