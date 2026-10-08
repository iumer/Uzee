import Foundation

/// What a backup file holds, shown before restoring (DATA-02).
public struct BackupSummary: Hashable, Sendable {
    public var createdAt: Date
    public var appVersion: String
    public var transactions: Int
    public var accounts: Int
    public var receipts: Int

    public init(createdAt: Date, appVersion: String, transactions: Int, accounts: Int, receipts: Int) {
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.transactions = transactions
        self.accounts = accounts
        self.receipts = receipts
    }
}

public enum BackupProblem: Error, Equatable, Sendable {
    /// Not a UZee backup, or cut short.
    case notABackup
    /// Wrong password, or the file was changed after it was made.
    case wrongPasswordOrDamaged
    /// Made by a newer UZee.
    case tooNew
    case weakPassword
    case failed

    public var message: String {
        switch self {
        case .notABackup: "This isn't a UZee backup file."
        case .wrongPasswordOrDamaged: "Wrong password, or the file is damaged. Nothing was changed."
        case .tooNew: "This backup is from a newer UZee. Update UZee first."
        case .weakPassword: "Use at least 8 characters."
        case .failed: "Couldn't finish. Nothing was changed."
        }
    }

    public static let minimumPasswordLength = 8
}
