import Foundation

public struct SequentialPasteQueue: Sendable {
    public private(set) var ids: [Int64] = []
    public private(set) var position = 0
    public init() {}
    public var nextID: Int64? { position < ids.count ? ids[position] : nil }
    public mutating func start(ids: [Int64]) { self.ids = ids; position = 0 }
    public mutating func advance() { if nextID != nil { position += 1 } }
    public mutating func stop() { ids = []; position = 0 }
}
