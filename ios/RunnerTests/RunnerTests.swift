import XCTest
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
