import CommonCrypto
import CryptoKit
import Foundation

/// The backup's sealing (DATA-02, SEC): a 256-bit key from the password with PBKDF2-HMAC-SHA256 and a random
/// salt, then AES-GCM, which also detects any change to the file. The password and key are never stored.
public enum BackupCrypto {
    /// OWASP's 2023 minimum for PBKDF2-SHA256; about half a second on a recent iPhone.
    public static let iterations = 600_000

    public enum Failure: Error { case keyDerivation }

    static func key(_ password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        // The count comes from the file's header: a damaged one must not crash or spin for hours.
        guard (1...5_000_000).contains(iterations) else { throw Failure.keyDerivation }
        var key = [UInt8](repeating: 0, count: 32)
        let passwordBytes = Array(password.utf8)
        let status = salt.withUnsafeBytes { saltBuffer in
            passwordBytes.withUnsafeBufferPointer { passwordBuffer in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     passwordBuffer.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                                     passwordBytes.count,
                                     saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), &key, key.count)
            }
        }
        guard status == kCCSuccess else { throw Failure.keyDerivation }
        return SymmetricKey(data: key)
    }

    public static func seal(_ plain: Data, password: String, salt: Data, iterations: Int) throws -> Data {
        let box = try AES.GCM.seal(plain, using: try key(password, salt: salt, iterations: iterations))
        guard let combined = box.combined else { throw Failure.keyDerivation }
        return combined
    }

    public static func open(_ sealed: Data, password: String, salt: Data, iterations: Int) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: try key(password, salt: salt, iterations: iterations))
    }
}
