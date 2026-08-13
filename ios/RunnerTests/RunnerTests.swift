import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {

  private var runnerBundle: Bundle {
    Bundle(for: AppDelegate.self)
  }

  func testWalletStorageChannelUsesStableProductNamespace() {
    XCTAssertEqual(
      WalletStoragePolicy.channelName,
      "com.utexo.wallet/storage_security"
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
}
