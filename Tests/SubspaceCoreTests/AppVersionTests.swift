import Testing
@testable import SubspaceCore

@Suite("Update check version comparison") struct AppVersionTests {
    @Test("GitHub tags are normalized")
    func normalizing() {
        #expect(AppVersion.normalized("v1.2.0") == "1.2.0")
        #expect(AppVersion.normalized(" 1.3.0\n") == "1.3.0")
    }
    @Test("Later releases are detected numerically, not alphabetically")
    func comparing() {
        #expect(AppVersion.isNewer("v1.3.0", than: "1.2.0"))
        #expect(AppVersion.isNewer("1.10.0", than: "1.9.9"))
        #expect(AppVersion.isNewer("2.0", than: "1.99.99"))
        #expect(!AppVersion.isNewer("v1.2.0", than: "1.2.0"))
        #expect(!AppVersion.isNewer("1.2", than: "1.2.0"))
        #expect(!AppVersion.isNewer("1.1.3", than: "1.2.0"))
        #expect(!AppVersion.isNewer("1.2.0-beta", than: "1.2.0"))
    }
}
