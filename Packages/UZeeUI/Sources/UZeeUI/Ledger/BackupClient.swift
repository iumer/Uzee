import Foundation
import UZeeCore

/// Encrypted backup and restore (DATA-02), injected like `LedgerClient`. The calls are slow (key stretching,
/// copying the database), so screens run them off the main thread.
public struct BackupClient: Sendable {
    /// Writes a backup file and returns where it is, ready to share or save to Files.
    public var makeBackup: @Sendable (_ password: String) throws -> URL
    public var inspect: @Sendable (_ file: Data, _ password: String) throws -> BackupSummary
    public var restore: @Sendable (_ file: Data, _ password: String) throws -> BackupSummary

    public init(makeBackup: @escaping @Sendable (String) throws -> URL,
                inspect: @escaping @Sendable (Data, String) throws -> BackupSummary,
                restore: @escaping @Sendable (Data, String) throws -> BackupSummary) {
        self.makeBackup = makeBackup
        self.inspect = inspect
        self.restore = restore
    }

    public static let unavailable = BackupClient(makeBackup: { _ in throw BackupProblem.failed },
                                                 inspect: { _, _ in throw BackupProblem.failed },
                                                 restore: { _, _ in throw BackupProblem.failed })
}
