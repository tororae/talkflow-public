import Foundation
import Testing
@testable import TalkFlowInfrastructure

/// An invented pair, and an expectation produced by this implementation rather
/// than observed anywhere.
///
/// It used to be a real `(user_id, device uuid)` read off this machine, because
/// that made the test evidence about KakaoTalk and not merely about ourselves.
/// That pair could not be published: the filename and the SQLCipher key come from
/// the *same* derivation, so the two numbers are the whole secret protecting a
/// KakaoTalk database at rest, and `KakaoKeyDerivation` beside them is the machine
/// that turns them into it.
///
/// What is left still catches what this test is for — any drift in the string
/// assembly, the two reversals, or the PBKDF2 parameters changes this string. What
/// it can no longer catch is an implementation that was wrong from the first day,
/// since it now agrees with itself. `derivationMatchesThisMachine` below is where
/// that half went: it needs a real pair, so it takes one from the environment and
/// nothing is written down.
private let oracleUUID = "00000000-0000-0000-0000-000000000000"
private let oracleUserID = 100_000_001
private let oracleDatabaseName =
    "05e66b9663655306d45fe637dd840852505b66d597b45bc143fbdec9e4ffdc3b47d115d23d9e7f"

@Test
func theDerivedDatabaseNameIsStableForAGivenPair() {
    let name = KakaoKeyDerivation.databaseName(userID: oracleUserID, deviceUUID: oracleUUID)

    #expect(name == oracleDatabaseName)
}

@Test
func theDerivedNameIsSeventyEightLowercaseHexCharacters() {
    let name = KakaoKeyDerivation.databaseName(userID: oracleUserID, deviceUUID: oracleUUID)

    #expect(name.count == 78)
    #expect(name.allSatisfy { $0.isHexDigit && !$0.isUppercase })
}

/// Two accounts on one Mac must land on different files; that separation is the
/// whole reason an account switch leaves the previous database behind.
@Test
func differentAccountsOnOneDeviceDeriveDifferentDatabases() {
    let first = KakaoKeyDerivation.databaseName(userID: oracleUserID, deviceUUID: oracleUUID)
    let second = KakaoKeyDerivation.databaseName(userID: oracleUserID + 1, deviceUUID: oracleUUID)

    #expect(first != second)
}

/// One account on two Macs must land on different files too — the device half of
/// the pair has to reach the output, or an account switch would be the only thing
/// that ever changed the name.
@Test
func oneAccountOnTwoDevicesDerivesDifferentDatabases() {
    let first = KakaoKeyDerivation.databaseName(userID: oracleUserID, deviceUUID: oracleUUID)
    let second = KakaoKeyDerivation.databaseName(
        userID: oracleUserID,
        deviceUUID: "11111111-1111-1111-1111-111111111111"
    )

    #expect(first != second)
}

@Test
func theDeviceHashIsBase64OfFiftyTwoBytes() {
    let hashed = KakaoKeyDerivation.hashedDeviceUUID(oracleUUID)

    #expect(Data(base64Encoded: hashed)?.count == 52)
}

/// The half the synthetic oracle above cannot carry: that this derivation is the
/// one KakaoTalk actually uses.
///
/// Skipped unless a real pair is handed in, because a real pair may not live in
/// this repository. Anyone can run it against their own Mac:
///
/// ```
/// TALKFLOW_KAKAO_USER_ID=… TALKFLOW_KAKAO_DEVICE_UUID=… \
///   swift test --filter derivationMatchesThisMachine
/// ```
///
/// It asserts nothing about which account it is — only that the name this code
/// derives is a file that exists in KakaoTalk's container. If it fails, the
/// derivation has drifted from KakaoTalk and every synthetic expectation above is
/// pinning the wrong thing.
/// `.enabled(if:)` rather than a guard that returns early: a test that quietly
/// passes when it did nothing is a test that reads as coverage it does not have.
/// Without the pair this one is reported as skipped, which is the truth.
@Test(.enabled(if: ProcessInfo.processInfo.environment["TALKFLOW_KAKAO_USER_ID"] != nil))
func derivationMatchesThisMachine() throws {
    let environment = ProcessInfo.processInfo.environment
    let userID = try #require(environment["TALKFLOW_KAKAO_USER_ID"].flatMap(Int.init))
    let deviceUUID = try #require(
        environment["TALKFLOW_KAKAO_DEVICE_UUID"],
        "TALKFLOW_KAKAO_USER_ID만 넘어왔습니다. 기기 UUID도 있어야 유도할 수 있습니다."
    )

    let derived = KakaoKeyDerivation.databaseName(userID: userID, deviceUUID: deviceUUID)
    let container = KatokEnvironment.kakaoContainerURL()
    let present = (try? FileManager.default.contentsOfDirectory(atPath: container.path)) ?? []

    #expect(
        present.contains { $0 == derived || $0.hasPrefix("\(derived).") },
        "유도한 이름이 카카오톡 컨테이너에 없습니다. 유도가 카카오톡과 어긋났거나, 넘긴 쌍이 이 기기의 것이 아닙니다."
    )
}
