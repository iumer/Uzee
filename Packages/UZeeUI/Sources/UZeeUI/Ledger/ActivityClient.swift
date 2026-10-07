import Foundation
import UZeeCore

/// M3 operations: Recently Deleted, categories, tags and receipts. Injected like `LedgerClient`.
public struct ActivityClient: Sendable {
    public var deletedTransactions: @Sendable () throws -> [MoneyTransaction]
    public var restore: @Sendable (UUID) throws -> Void
    /// "Delete now" from Recently Deleted; also removes receipt files.
    public var purge: @Sendable ([UUID]) throws -> Void
    public var createCategory: @Sendable (String, UUID?) throws -> SpendCategory
    public var renameCategory: @Sendable (UUID, String) throws -> Void
    public var setCategoryHidden: @Sendable (Bool, UUID) throws -> Void
    public var reorderCategories: @Sendable ([UUID]) throws -> Void
    public var deleteCategory: @Sendable (UUID) throws -> Void
    public var mergeCategory: @Sendable (UUID, UUID) throws -> Void
    public var categoryUsage: @Sendable () throws -> [UUID: Int]
    public var rememberedCategories: @Sendable () throws -> [String: UUID]
    public var tags: @Sendable () throws -> [MoneyTag]
    public var createTag: @Sendable (String) throws -> MoneyTag
    public var deleteTag: @Sendable (UUID) throws -> Void
    public var tagMap: @Sendable () throws -> [UUID: Set<UUID>]
    public var setTags: @Sendable (Set<UUID>, UUID) throws -> Void
    public var attachments: @Sendable (UUID) throws -> [ReceiptFile]
    public var withAttachments: @Sendable () throws -> Set<UUID>
    /// Writes the bytes to protected storage and records them on the transaction.
    public var addAttachment: @Sendable (UUID, ReceiptFile.Kind, Data) throws -> ReceiptFile
    public var removeAttachment: @Sendable (UUID) throws -> Void
    public var fileURL: @Sendable (ReceiptFile) -> URL?

    public init(deletedTransactions: @escaping @Sendable () throws -> [MoneyTransaction],
                restore: @escaping @Sendable (UUID) throws -> Void,
                purge: @escaping @Sendable ([UUID]) throws -> Void,
                createCategory: @escaping @Sendable (String, UUID?) throws -> SpendCategory,
                renameCategory: @escaping @Sendable (UUID, String) throws -> Void,
                setCategoryHidden: @escaping @Sendable (Bool, UUID) throws -> Void,
                reorderCategories: @escaping @Sendable ([UUID]) throws -> Void,
                deleteCategory: @escaping @Sendable (UUID) throws -> Void,
                mergeCategory: @escaping @Sendable (UUID, UUID) throws -> Void,
                categoryUsage: @escaping @Sendable () throws -> [UUID: Int],
                rememberedCategories: @escaping @Sendable () throws -> [String: UUID],
                tags: @escaping @Sendable () throws -> [MoneyTag],
                createTag: @escaping @Sendable (String) throws -> MoneyTag,
                deleteTag: @escaping @Sendable (UUID) throws -> Void,
                tagMap: @escaping @Sendable () throws -> [UUID: Set<UUID>],
                setTags: @escaping @Sendable (Set<UUID>, UUID) throws -> Void,
                attachments: @escaping @Sendable (UUID) throws -> [ReceiptFile],
                withAttachments: @escaping @Sendable () throws -> Set<UUID>,
                addAttachment: @escaping @Sendable (UUID, ReceiptFile.Kind, Data) throws -> ReceiptFile,
                removeAttachment: @escaping @Sendable (UUID) throws -> Void,
                fileURL: @escaping @Sendable (ReceiptFile) -> URL?) {
        self.deletedTransactions = deletedTransactions
        self.restore = restore
        self.purge = purge
        self.createCategory = createCategory
        self.renameCategory = renameCategory
        self.setCategoryHidden = setCategoryHidden
        self.reorderCategories = reorderCategories
        self.deleteCategory = deleteCategory
        self.mergeCategory = mergeCategory
        self.categoryUsage = categoryUsage
        self.rememberedCategories = rememberedCategories
        self.tags = tags
        self.createTag = createTag
        self.deleteTag = deleteTag
        self.tagMap = tagMap
        self.setTags = setTags
        self.attachments = attachments
        self.withAttachments = withAttachments
        self.addAttachment = addAttachment
        self.removeAttachment = removeAttachment
        self.fileURL = fileURL
    }

    /// No database: empty and read-only.
    public static let unavailable = ActivityClient(
        deletedTransactions: { [] }, restore: { _ in throw CoreError.notFound }, purge: { _ in },
        createCategory: { _, _ in throw CoreError.notFound }, renameCategory: { _, _ in throw CoreError.notFound },
        setCategoryHidden: { _, _ in throw CoreError.notFound }, reorderCategories: { _ in },
        deleteCategory: { _ in throw CoreError.notFound }, mergeCategory: { _, _ in throw CoreError.notFound },
        categoryUsage: { [:] }, rememberedCategories: { [:] }, tags: { [] }, createTag: { _ in throw CoreError.notFound },
        deleteTag: { _ in }, tagMap: { [:] }, setTags: { _, _ in throw CoreError.notFound },
        attachments: { _ in [] }, withAttachments: { [] }, addAttachment: { _, _, _ in throw CoreError.notFound },
        removeAttachment: { _ in }, fileURL: { _ in nil })
}
