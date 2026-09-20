import Foundation
import GRDB

/// ClipboardItem 的 GRDB 持久化能力。
/// 单独放在扩展文件，让领域模型 ClipboardItem 本身与存储实现解耦。
extension ClipboardItem: FetchableRecord, MutablePersistableRecord {
    /// 数据库表名
    public static let databaseTableName = "clipboardItem"

    /// 列名定义，供查询构造使用
    enum Columns {
        static let id = Column("id")
        static let type = Column("type")
        static let content = Column("content")
        static let sourceApp = Column("sourceApp")
        static let createdAt = Column("createdAt")
        static let isSensitive = Column("isSensitive")
        static let contentHash = Column("contentHash")
    }

    /// 插入后回填自增主键
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
