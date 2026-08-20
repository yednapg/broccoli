import Foundation

public enum DiagnosticMetric: String, Codable, Equatable, Sendable {
    case hotKeyToPanel
    case queryToResults
    case returnToDispatch
}

public struct DiagnosticSample: Codable, Sendable {
    public let metric: DiagnosticMetric
    public let durationMilliseconds: Double
    public let recordedAt: Date

    public init(metric: DiagnosticMetric, durationMilliseconds: Double, recordedAt: Date = Date()) {
        self.metric = metric
        self.durationMilliseconds = durationMilliseconds
        self.recordedAt = recordedAt
    }
}

public actor DiagnosticsStore {
    private let fileURL: URL
    private let maximumSamples: Int
    private let maximumAge: TimeInterval
    private var samples: [DiagnosticSample] = []
    private var persistenceTask: Task<Void, Never>?

    public init(
        fileURL: URL,
        maximumSamples: Int = 500,
        maximumAge: TimeInterval = 30 * 86_400
    ) {
        self.fileURL = fileURL
        self.maximumSamples = maximumSamples
        self.maximumAge = maximumAge
    }

    public func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([DiagnosticSample].self, from: data) else { return }
        samples = bounded(decoded, now: Date())
    }

    public func append(_ sample: DiagnosticSample) async {
        samples.append(sample)
        samples = bounded(samples, now: sample.recordedAt)
        schedulePersistence()
    }

    public func flush() {
        persistenceTask?.cancel()
        persistenceTask = nil
        try? persist()
    }

    public func export(to destination: URL) throws {
        samples = bounded(samples, now: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(samples).write(to: destination, options: .atomic)
    }

    private func persist() throws {
        samples = bounded(samples, now: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(samples).write(to: fileURL, options: .atomic)
    }

    private func schedulePersistence() {
        guard persistenceTask == nil else { return }
        persistenceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self else { return }
            await self.persistScheduledSamples()
        }
    }

    private func persistScheduledSamples() {
        persistenceTask = nil
        try? persist()
    }

    private func bounded(_ values: [DiagnosticSample], now: Date) -> [DiagnosticSample] {
        let cutoff = now.addingTimeInterval(-maximumAge)
        return Array(values.filter { $0.recordedAt >= cutoff }.suffix(maximumSamples))
    }
}
