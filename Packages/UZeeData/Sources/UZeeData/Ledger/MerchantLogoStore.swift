import Foundation
import GRDB
import UZeeCore

public struct MerchantLogo: Sendable {
    public let payeeName: String
    public let imageData: Data?
    public let sourceURL: String?
    public let fetchedAt: Date

    public init(payeeName: String, imageData: Data?, sourceURL: String?, fetchedAt: Date = Date()) {
        self.payeeName = payeeName
        self.imageData = imageData
        self.sourceURL = sourceURL
        self.fetchedAt = fetchedAt
    }
}

extension EventStore {
    public func merchantLogos() throws -> [MerchantLogo] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM merchant_logo WHERE image_data IS NOT NULL")
                .map { row in
                    MerchantLogo(payeeName: row["payee_name"],
                                 imageData: row["image_data"],
                                 sourceURL: row["source_url"],
                                 fetchedAt: Timestamp.date(row["fetched_at"]))
                }
        }
    }

    public func saveMerchantLogo(_ logo: MerchantLogo) throws {
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO merchant_logo (payee_name, image_data, source_url, fetched_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(payee_name) DO UPDATE SET image_data = excluded.image_data,
                    source_url = excluded.source_url, fetched_at = excluded.fetched_at
                """, arguments: [logo.payeeName, logo.imageData, logo.sourceURL, Timestamp.from(logo.fetchedAt)])
        }
    }

    public func deleteMerchantLogo(payeeName: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM merchant_logo WHERE payee_name = ?", arguments: [payeeName])
        }
    }
}
