import Foundation
import BroccoliCore

@MainActor
final class CurrencyRateService {
    private static let refreshAgeLimit: TimeInterval = 12 * 60 * 60
    private static let frankfurterURL = URL(string: "https://api.frankfurter.dev/v2/rates?base=usd")!
    private static let fawazahmedURL = URL(
        string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json"
    )!

    private let store: CurrencyRateStore
    private let isEnabled: @MainActor () -> Bool
    private let onUpdate: @MainActor (CurrencyRateSnapshot?) -> Void
    private let session: URLSession
    private var refreshTask: Task<Void, Never>?

    init(
        store: CurrencyRateStore,
        isEnabled: @escaping @MainActor () -> Bool,
        onUpdate: @escaping @MainActor (CurrencyRateSnapshot?) -> Void
    ) {
        self.store = store
        self.isEnabled = isEnabled
        self.onUpdate = onUpdate

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 8
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    func start() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.runStart()
        }
    }

    private func runStart() async {
        let cached = await store.load()
        guard !Task.isCancelled else { return }
        onUpdate(cached)

        guard isEnabled() else { return }
        guard needsRefresh(cached) else { return }
        guard !Task.isCancelled else { return }

        await refresh(replacing: cached)
    }

    private func needsRefresh(_ cached: CurrencyRateSnapshot?) -> Bool {
        guard let cached else { return true }
        if Date().timeIntervalSince(cached.fetchedAt) > Self.refreshAgeLimit {
            return true
        }
        return cached.freshness(now: Date(), calendar: .current) != .current
    }

    private func refresh(replacing existing: CurrencyRateSnapshot?) async {
        guard let incoming = await fetchSnapshot() else { return }
        guard !Task.isCancelled else { return }

        guard let accepted = CurrencyRateDecoding.accepting(incoming, replacing: existing) else {
            return
        }
        guard !Task.isCancelled else { return }

        await store.save(accepted)
        guard !Task.isCancelled else { return }
        onUpdate(accepted)
    }

    private func fetchSnapshot() async -> CurrencyRateSnapshot? {
        let fetchedAt = Date()
        if let data = await fetchData(from: Self.frankfurterURL),
           let snapshot = CurrencyRateDecoding.frankfurter(data, fetchedAt: fetchedAt) {
            return snapshot
        }
        guard !Task.isCancelled else { return nil }
        if let data = await fetchData(from: Self.fawazahmedURL),
           let snapshot = CurrencyRateDecoding.fawazahmed(data, fetchedAt: fetchedAt) {
            return snapshot
        }
        return nil
    }

    private func fetchData(from url: URL) async -> Data? {
        do {
            let (data, _) = try await session.data(from: url)
            return data
        } catch {
            return nil
        }
    }
}
