import Flutter
import UIKit
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {

  func testCarPlayEntitlementExists() {
    let testFileDir = (String(#file) as NSString).deletingLastPathComponent
    let entitlementsPath = (testFileDir as NSString)
      .deletingLastPathComponent
      .appending("/Runner/Runner.entitlements")

    let fileManager = FileManager.default
    XCTAssertTrue(
      fileManager.fileExists(atPath: entitlementsPath),
      "Runner.entitlements must exist at \(entitlementsPath)"
    )

    guard let data = fileManager.contents(atPath: entitlementsPath),
          let plist = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
          ) as? [String: Any]
    else {
      XCTFail("Failed to read Runner.entitlements as plist")
      return
    }

    XCTAssertEqual(
      plist["com.apple.developer.carplay-audio"] as? Bool,
      true,
      "com.apple.developer.carplay-audio entitlement must be true"
    )
  }

  func testInfoPlistCarPlaySceneConfig() {
    guard let infoPlist = Bundle.main.infoDictionary,
          let sceneManifest = infoPlist["UIApplicationSceneManifest"] as? [String: Any],
          let configs = sceneManifest["UISceneConfigurations"] as? [String: Any],
          let cpConfigs = configs["CPTemplateApplicationSceneSessionRoleApplication"] as? [[String: Any]]
    else {
      XCTFail("Info.plist missing CPTemplateApplicationSceneSessionRoleApplication")
      return
    }

    XCTAssertFalse(cpConfigs.isEmpty, "CarPlay scene configuration must not be empty")

    let firstConfig = cpConfigs[0]
    XCTAssertEqual(
      firstConfig["UISceneConfigurationName"] as? String,
      "CarPlay"
    )
    XCTAssertEqual(
      firstConfig["UISceneClassName"] as? String,
      "CPTemplateApplicationScene"
    )
  }

}
