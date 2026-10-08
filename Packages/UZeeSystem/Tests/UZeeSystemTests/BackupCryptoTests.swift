import Foundation
import Testing
@testable import UZeeSystem

@Suite("Backup sealing")
struct BackupCryptoTests {
    @Test("SEC-005 AES-GCM with a PBKDF2 key: opens with the password, refuses a wrong one or a changed byte")
    func sealing() throws {
        let salt = Data((0..<16).map { UInt8($0) })
        let sealed = try BackupCrypto.seal(Data("ledger".utf8), password: "correct horse", salt: salt, iterations: 1_000)
        #expect(try BackupCrypto.open(sealed, password: "correct horse", salt: salt, iterations: 1_000) == Data("ledger".utf8))
        #expect(throws: (any Error).self) { try BackupCrypto.open(sealed, password: "wrong horse", salt: salt, iterations: 1_000) }
        var changed = sealed
        changed[changed.count - 1] ^= 1
        #expect(throws: (any Error).self) { try BackupCrypto.open(changed, password: "correct horse", salt: salt, iterations: 1_000) }
    }
}
