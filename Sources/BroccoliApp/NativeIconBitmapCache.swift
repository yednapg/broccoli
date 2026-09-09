import Foundation

/// A strict bitmap-cost LRU. NSCache cost limits are advisory; icon generations must not
/// accumulate indefinitely as windows request different appearances, sizes, and scales.
@MainActor
final class NativeIconBitmapCache {
    private final class Entry {
        let icon: MaterializedSystemSettingsIcon
        var access: UInt64
        init(icon: MaterializedSystemSettingsIcon, access: UInt64) {
            self.icon = icon
            self.access = access
        }
    }
    private let limit: Int
    private var entries: [IconCacheKey: Entry] = [:]
    private var access: UInt64 = 0
    private(set) var cost = 0

    init(costLimit: Int) { limit = max(1, costLimit) }

    func image(for key: IconCacheKey) -> MaterializedSystemSettingsIcon? {
        guard let entry = entries[key] else { return nil }
        access &+= 1
        entry.access = access
        return entry.icon
    }

    @discardableResult
    func insert(_ icon: MaterializedSystemSettingsIcon, for key: IconCacheKey) -> Bool {
        guard icon.cost <= limit else { return false }
        if let previous = entries.removeValue(forKey: key) { cost -= previous.icon.cost }
        while cost + icon.cost > limit,
              let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key {
            if let removed = entries.removeValue(forKey: oldest) { cost -= removed.icon.cost }
        }
        access &+= 1
        entries[key] = Entry(icon: icon, access: access)
        cost += icon.cost
        return true
    }
}
