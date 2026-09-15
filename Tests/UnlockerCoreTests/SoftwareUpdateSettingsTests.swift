import Foundation
import Testing
@testable import UnlockerCore

@Test func developmentBuildsNeverEnableUpdates() {
    let info: [String: Any] = ["SUFeedURL": SoftwareUpdateSettings.feedURL,
                               "SUPublicEDKey": Data(repeating: 0, count: 32).base64EncodedString()]
    #expect(!SoftwareUpdateSettings(info: info).isEnabled)
}
@Test func packagedBuildRequiresLatchFeedAndValidPublicKey() {
    let good: [String: Any] = ["LatchUpdatesEnabled": true, "SUFeedURL": SoftwareUpdateSettings.feedURL,
                               "SUPublicEDKey": Data(repeating: 0, count: 32).base64EncodedString()]
    #expect(SoftwareUpdateSettings(info: good).isEnabled)
    for change in [["SUFeedURL": "https://example.com/appcast.xml"], ["SUPublicEDKey": "invalid"]] {
        #expect(!SoftwareUpdateSettings(info: good.merging(change) { _, new in new }).isEnabled)
    }
}
@Test func stableUsersExcludeBetaAndTestUsersIncludeIt() {
    #expect(SoftwareUpdateSettings.channels(includeTestBuilds: false).isEmpty)
    #expect(SoftwareUpdateSettings.channels(includeTestBuilds: true) == ["beta"])
}
