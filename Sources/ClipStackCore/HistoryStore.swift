import Foundation
import GRDB

/// 剪贴板历史数据存储，基于 GRDB (SQLite)
public final class HistoryStore: Sendable {
    private let dbQueue: DatabaseQueue
    private let maxItems: Int

    // MARK: - 初始化

    /// 生产环境：持久化到本地文件
    public init(path: String, maxItems: Int = 500) throws {
        let dbURL = URL(fileURLWithPath: path)
        // 确保目录存在
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.dbQueue = try DatabaseQueue(path: path)
        self.maxItems = maxItems
        try migrate()
    }

    /// 测试环境：内存数据库
    public static func inMemory(maxItems: Int = 500) throws -> HistoryStore {
        let queue = try DatabaseQueue()
        let store = HistoryStore(queue: queue, maxItems: maxItems)
        try store.migrate()
        return store
    }

    private init(queue: DatabaseQueue, maxItems: Int) {
        self.dbQueue = queue
        self.maxItems = maxItems
    }

    // MARK: - 建表迁移

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: ClipboardItem.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("type", .text).notNull()
                t.column("content", .text).notNull()
                t.column("sourceApp", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("isSensitive", .boolean).notNull().defaults(to: false)
            }
            // 按拷贝时间倒序索引，加速最近条目查询
            try db.create(index: "idx_createdAt", on: ClipboardItem.databaseTableName, columns: ["createdAt"])
        }

        migrator.registerMigration("v2") { db in
            try db.alter(table: ClipboardItem.databaseTableName) { t in
                t.add(column: "contentHash", .text)
            }
            // 图片按内容哈希全局去重
            try db.create(
                index: "idx_imageContentHash",
                on: ClipboardItem.databaseTableName,
                columns: ["contentHash"]
            )
        }

        migrator.registerMigration("v3") { db in
            try db.alter(table: ClipboardItem.databaseTableName) { t in
                t.add(column: "ocrText", .text)
                t.add(column: "isFavorite", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "idx_favoriteCreatedAt", on: ClipboardItem.databaseTableName, columns: ["isFavorite", "createdAt"])
        }

        migrator.registerMigration("v4") { db in
            try db.alter(table: ClipboardItem.databaseTableName) { t in
                t.add(column: "note", .text)
            }
        }

        migrator.registerMigration("v5") { db in
            try db.alter(table: ClipboardItem.databaseTableName) { t in
                t.add(column: "deletionDeadline", .datetime)
                t.add(column: "tags", .text)
            }
        }
        try migrator.migrate(dbQueue)
    }

    // MARK: - 增 / 查 / 删

    /// 保存一条剪贴板记录。
    /// - 图片：只要 contentHash 已存在，就更新已有记录的时间戳，避免重复图片占空间。
    /// - 文本/文件：若与最新一条内容+类型完全相同，则更新该条的时间戳而非新建。
    @discardableResult
    public func save(_ item: ClipboardItem) throws -> ClipboardItem {
        try dbQueue.write { db in
            var mutable = item

            if item.type == .image, let contentHash = item.contentHash {
                if let existing = try ClipboardItem
                    .filter(ClipboardItem.Columns.deletionDeadline == nil)
                    .filter(ClipboardItem.Columns.type == ClipboardItemType.image.rawValue)
                    .filter(ClipboardItem.Columns.contentHash == contentHash)
                    .order(ClipboardItem.Columns.createdAt.desc)
                    .limit(1)
                    .fetchOne(db) {
                    var updated = existing
                    updated.createdAt = item.createdAt
                    // Duplicate captures must not erase user-owned metadata.
                    updated.isFavorite = existing.isFavorite
                    updated.ocrText = existing.ocrText
                    let existingFileExists = FileManager.default.fileExists(atPath: existing.content)
                    let newFileExists = FileManager.default.fileExists(atPath: item.content)
                    if !existingFileExists && newFileExists {
                        updated.content = item.content
                    }
                    if let sourceApp = item.sourceApp {
                        updated.sourceApp = sourceApp
                    }
                    try updated.update(db)
                    return updated
                }
            }

            // 文本和普通文件保留原来的连续重复去重逻辑。
            if let latest = try ClipboardItem
                .filter(ClipboardItem.Columns.deletionDeadline == nil)
                .order(ClipboardItem.Columns.createdAt.desc)
                .limit(1)
                .fetchOne(db),
               latest.type == item.type,
               latest.content == item.content {
                // 连续相同，更新时间戳
                var updated = latest
                updated.createdAt = item.createdAt
                try updated.update(db)
                return updated
            } else {
                // 新记录
                try mutable.insert(db)
                return mutable
            }
        }
    }

    /// 为旧版本图片记录补齐内容哈希。
    public func backfillImageHashes(with imageStorage: ImageStorage) throws {
        try dbQueue.write { db in
            let items = try ClipboardItem
                .filter(ClipboardItem.Columns.type == ClipboardItemType.image.rawValue)
                .filter(ClipboardItem.Columns.contentHash == nil)
                .fetchAll(db)

            for var item in items {
                let url = URL(fileURLWithPath: item.content)
                guard let hash = try? ImageStorage.sha256File(at: url) else { continue }
                item.contentHash = hash
                try item.update(db)
            }
        }
    }

    /// 获取全部历史（按拷贝时间倒序）
    public func all(includingPendingDeletion: Bool = false) throws -> [ClipboardItem] {
        try dbQueue.read { db in
            try ClipboardItem
                .filter(includingPendingDeletion || ClipboardItem.Columns.deletionDeadline == nil)
                .order(ClipboardItem.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// 按条件查询
    public func items(matching filter: HistoryFilter) throws -> [ClipboardItem] {
        try dbQueue.read { db in
            var query = ClipboardItem.filter(ClipboardItem.Columns.deletionDeadline == nil)

            if let type = filter.type {
                query = query.filter(ClipboardItem.Columns.type == type.rawValue)
            }

            if let search = filter.searchText, !search.isEmpty {
                query = query.filter(
                    ClipboardItem.Columns.content.like("%\(search)%") ||
                    ClipboardItem.Columns.ocrText.like("%\(search)%") ||
                    ClipboardItem.Columns.note.like("%\(search)%")
                )
            }

            return try query
                .order(ClipboardItem.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    public func scheduleDeletion(id: Int64, now: Date = Date()) throws {
        try dbQueue.write { db in
            guard var item = try ClipboardItem.fetchOne(db, key: id), item.deletionDeadline == nil else { return }
            item.deletionDeadline = now.addingTimeInterval(10)
            try item.update(db)
        }
    }

    @discardableResult
    public func undoDeletion(id: Int64, now: Date = Date()) throws -> Bool {
        try dbQueue.write { db in
            guard var item = try ClipboardItem.fetchOne(db, key: id),
                  let deadline = item.deletionDeadline, deadline > now else { return false }
            item.deletionDeadline = nil
            try item.update(db)
            return true
        }
    }

    @discardableResult
    public func finalizeDeletions(now: Date = Date()) throws -> Int {
        try dbQueue.write { db in
            try ClipboardItem.filter(ClipboardItem.Columns.deletionDeadline <= now).deleteAll(db)
        }
    }

    public func updateFavorite(id: Int64, isFavorite: Bool) throws {
        try dbQueue.write { db in
            guard var item = try ClipboardItem.fetchOne(db, key: id) else { return }
            item.isFavorite = isFavorite
            try item.update(db)
        }
    }

    public func updateOCRText(id: Int64, text: String) throws {
        try dbQueue.write { db in
            guard var item = try ClipboardItem.fetchOne(db, key: id) else { return }
            item.ocrText = text
            try item.update(db)
        }
    }

    public func updateTags(id: Int64, tags: String) throws {
        try dbQueue.write { db in
            guard var item = try ClipboardItem.fetchOne(db, key: id) else { return }
            item.tags = tags
            let names = item.tagNames
            item.tags = names.isEmpty ? nil : names.joined(separator: ", ")
            try item.update(db)
        }
    }

    public func updateNote(id: Int64, note: String?) throws {
        try dbQueue.write { db in
            guard var item = try ClipboardItem.fetchOne(db, key: id) else { return }
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            item.note = trimmed?.isEmpty == true ? nil : trimmed
            try item.update(db)
        }
    }

    @discardableResult
    public func deleteExpired(olderThan date: Date) throws -> [ClipboardItem] {
        try dbQueue.write { db in
            let items = try ClipboardItem
                .filter(ClipboardItem.Columns.isFavorite == false)
                .filter(ClipboardItem.Columns.deletionDeadline == nil)
                .filter(ClipboardItem.Columns.createdAt < date)
                .fetchAll(db)
            for item in items { _ = try item.delete(db) }
            return items
        }
    }

    /// 默认清空普通历史；显式传入 includingFavorites 才会删除收藏。
    public func deleteAll(includingFavorites: Bool = false) throws {
        _ = try dbQueue.write { db in
            try ClipboardItem.filter(includingFavorites || ClipboardItem.Columns.isFavorite == false).deleteAll(db)
        }
    }

    // MARK: - 容量管理

    /// 删除超出 maxItems 限制的最旧记录，返回被删除的记录列表
    @discardableResult
    public func enforceCapacity() throws -> [ClipboardItem] {
        try dbQueue.write { db in
            let normalCount = try ClipboardItem.filter(ClipboardItem.Columns.isFavorite == false)
                .filter(ClipboardItem.Columns.deletionDeadline == nil).fetchCount(db)
            guard normalCount > maxItems else { return [] }

            let toDelete = normalCount - maxItems
            // 查出最旧的 N 条普通历史；收藏永不因容量淘汰
            let oldest = try ClipboardItem
                .filter(ClipboardItem.Columns.isFavorite == false)
                .filter(ClipboardItem.Columns.deletionDeadline == nil)
                .order(ClipboardItem.Columns.createdAt.asc)
                .limit(toDelete)
                .fetchAll(db)

            // 删除
            for item in oldest {
                try item.delete(db)
            }

            return oldest
        }
    }

    /// 执行容量限制，并清理 images 目录中已经没有数据库记录引用的图片。
    public func enforceCapacityAndCleanupImages(imageStorage: ImageStorage) throws {
        try enforceCapacity()
        let items = try all(includingPendingDeletion: true)
        let validPaths = Set(items.filter { $0.type == .image }.map(\.content))
        try imageStorage.deleteUnreferencedFiles(validPaths: validPaths)
    }
}
