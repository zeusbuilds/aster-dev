import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {

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
}
