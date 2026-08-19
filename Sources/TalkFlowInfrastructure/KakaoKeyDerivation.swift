import CommonCrypto
import Foundation

/// Derives the names KakaoTalk gives its per-account databases.
///
/// Both the filename and the encryption key come from `(user_id, device uuid)`,
/// which is why signing into a different account produces a different file and
/// leaves the previous one behind. TalkFlow only needs the filename: it uses the
/// derivation to work out which database belongs to which account, and lets the
/// connector do the decrypting.
///
/// Ported from the derivation kakaocli and katok both implement.
enum KakaoKeyDerivation {
    private static let iterations: UInt32 = 100_000
    private static let derivedLength = 128

    /// The 78-hex filename KakaoTalk uses for this account on this device.
    static func databaseName(userID: Int, deviceUUID: String) -> String {
        let password = [".", "F", String(userID), "A", "F", String(deviceUUID.reversed()), ".", "|"]
            .joined(separator: ".")
        let salt = String(hashedDeviceUUID(deviceUUID).reversed())
        let hex = pbkdf2(password: password, salt: salt)
            .map { String(format: "%02x", $0) }
            .joined()

        let start = hex.index(hex.startIndex, offsetBy: 28)
        let end = hex.index(start, offsetBy: 78)
        return String(hex[start..<end])
    }

    /// `base64(sha1(uuid) + sha256(uuid))`.
    static func hashedDeviceUUID(_ uuid: String) -> String {
        let data = Data(uuid.utf8)
        var sha1 = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        var sha256 = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA1(bytes.baseAddress, CC_LONG(data.count), &sha1)
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &sha256)
        }
        return Data(sha1 + sha256).base64EncodedString()
    }

    private static func pbkdf2(password: String, salt: String) -> [UInt8] {
        var derived = [UInt8](repeating: 0, count: derivedLength)
        let saltBytes = [UInt8](salt.utf8)
        _ = password.withCString { passwordBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes,
                strlen(passwordBytes),
                saltBytes,
                saltBytes.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                iterations,
                &derived,
                derivedLength
            )
        }
        return derived
    }
}
