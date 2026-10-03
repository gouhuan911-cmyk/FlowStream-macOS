import Foundation

/// 负责下载历史记录的持久化读写与管理
public final class HistoryManager {
    public static let shared = HistoryManager()
    
    private let kHistoryStorageKey = "FlowStream_DownloadHistory_v2"
    private let lock = NSLock()
    
    private init() {}
    
    /// 加载全部历史记录（最新完成的排在最前）
    public func loadHistory() -> [DownloadHistoryItem] {
        lock.lock()
        defer { lock.unlock() }
        
        guard let data = UserDefaults.standard.data(forKey: kHistoryStorageKey) else {
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            let list = try decoder.decode([DownloadHistoryItem].self, from: data)
            return list.sorted { $0.completedAt > $1.completedAt }
        } catch {
            return []
        }
    }
    
    /// 添加一条历史记录
    public func addHistory(item: DownloadHistoryItem) {
        lock.lock()
        defer { lock.unlock() }
        
        var current = (try? JSONDecoder().decode([DownloadHistoryItem].self, from: UserDefaults.standard.data(forKey: kHistoryStorageKey) ?? Data())) ?? []
        
        // 避免重复路径堆叠
        current.removeAll { $0.filePath == item.filePath }
        current.insert(item, at: 0)
        
        // 限制最多保存 200 条历史记录
        if current.count > 200 {
            current = Array(current.prefix(200))
        }
        
        if let encoded = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(encoded, forKey: kHistoryStorageKey)
        }
    }
    
    /// 删除单条历史记录
    public func removeHistory(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        
        var current = (try? JSONDecoder().decode([DownloadHistoryItem].self, from: UserDefaults.standard.data(forKey: kHistoryStorageKey) ?? Data())) ?? []
        current.removeAll { $0.id == id }
        
        if let encoded = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(encoded, forKey: kHistoryStorageKey)
        }
    }
    
    /// 清空全部历史记录
    public func clearAllHistory() {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: kHistoryStorageKey)
    }
}
