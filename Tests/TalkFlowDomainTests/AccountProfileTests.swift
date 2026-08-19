import Testing
@testable import TalkFlowDomain

@Test
func accountProfileKeepsUserLabelSeparateFromConnectionFingerprint() {
    let profile = AccountProfile(label: "개인 계정", fingerprint: "account-fingerprint")

    #expect(profile.label == "개인 계정")
    #expect(profile.fingerprint == "account-fingerprint")
}
