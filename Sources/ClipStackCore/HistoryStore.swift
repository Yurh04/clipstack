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

        try migrator.migrate(dbQueue)
    }

    // MARK: - 增 / 查 / 删

    /// 保存一条剪贴板记录。
    /// 若与最新一条内容+类型完全相同，则更新该条的时间戳而非新建。
    @discardableResult
    public func save(_ item: ClipboardItem) throws -> ClipboardItem {
        try dbQueue.write { db in
            var mutable = item

            // 去重逻辑：查最新一条
            if let latest = try ClipboardItem
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

    /// 获取全部历史（按拷贝时间倒序）
    public func all() throws -> [ClipboardItem] {
        try dbQueue.read { db in
            try ClipboardItem
                .order(ClipboardItem.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// 按条件查询
    public func items(matching filter: HistoryFilter) throws -> [ClipboardItem] {
        try dbQueue.read { db in
            var query = ClipboardItem.all()

            if let type = filter.type {
                query = query.filter(ClipboardItem.Columns.type == type.rawValue)
            }

            if let search = filter.searchText, !search.isEmpty {
                query = query.filter(ClipboardItem.Columns.content.like("%\(search)%"))
            }

            return try query
                .order(ClipboardItem.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// 清空全部历史
    public func deleteAll() throws {
        _ = try dbQueue.write { db in
            try ClipboardItem.deleteAll(db)
        }
    }

    // MARK: - 容量管理

    /// 删除超出 maxItems 限制的最旧记录，返回被删除的记录列表
    @discardableResult
    public func enforceCapacity() throws -> [ClipboardItem] {
        try dbQueue.write { db in
            let count = try ClipboardItem.fetchCount(db)
            guard count > maxItems else { return [] }

            let toDelete = count - maxItems
            // 查出最旧的 N 条
            let oldest = try ClipboardItem
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
}
