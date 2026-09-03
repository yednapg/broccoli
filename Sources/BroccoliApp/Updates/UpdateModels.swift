import Foundation

enum UpdateChannel: String, CaseIterable, Identifiable, Sendable {
    case stable
    case beta

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var checkInterval: TimeInterval {
        switch self {
        case .stable: 24 * 60 * 60
        case .beta: 6 * 60 * 60
        }
    }

    var allowedSparkleChannels: Set<String> {
        switch self {
        case .stable: []
        case .beta: [UpdateChannel.beta.rawValue]
        }
    }
}

enum UpdatePriority: String, CaseIterable, Sendable {
    case routine
    case important
    case critical
}

enum UpdatePhase: String, Equatable, Sendable {
    case permissionRequest
    case idle
    case checking
    case available
    case downloading
    case extracting
    case ready
    case installing
    case completed
    case current
    case cancelled
    case failed
}

struct UpdateCandidate: Equatable, Sendable {
    let version: String
    let build: String
    let title: String
    let priority: UpdatePriority
    let isCritical: Bool
    let isInformationalOnly: Bool
    let informationURL: URL?
}

enum UpdateActionPolicy: Equatable, Sendable {
    case informationOnly
    case routine
    case important
    case critical

    init(priority: UpdatePriority, isCritical: Bool, isInformationalOnly: Bool) {
        if isInformationalOnly {
            self = .informationOnly
        } else if priority == .critical || isCritical {
            self = .critical
        } else if priority == .important {
            self = .important
        } else {
            self = .routine
        }
    }

    var allowsPermanentSkip: Bool { self == .routine }
    var allowsAutomaticDownload: Bool {
        self == .important || self == .critical
    }
}

enum UpdatePriorityParser {
    static func parse(properties: [AnyHashable: Any], isCriticalUpdate: Bool) -> UpdatePriority {
        if isCriticalUpdate { return .critical }
        guard let rawValue = findPriority(in: properties)?.lowercased(),
              let priority = UpdatePriority(rawValue: rawValue) else {
            return .routine
        }
        return priority
    }

    private static func findPriority(in value: Any) -> String? {
        if let dictionary = value as? [AnyHashable: Any] {
            for (key, child) in dictionary {
                let normalizedKey = String(describing: key).lowercased()
                if normalizedKey == "broccoli:priority" || normalizedKey == "priority" {
                    if let string = child as? String { return string }
                    if let element = child as? [AnyHashable: Any],
                       let content = element["content"] as? String {
                        return content
                    }
                }
                if let nested = findPriority(in: child) { return nested }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let nested = findPriority(in: child) { return nested }
            }
        }
        return nil
    }
}

enum UpdateEligibility {
    static func isNewerBuild(candidate: String, installed: String) -> Bool {
        guard let candidateNumber = UInt64(candidate),
              let installedNumber = UInt64(installed) else { return false }
        return candidateNumber > installedNumber
    }
}

struct UpdatePresentationDecision: Equatable, Sendable {
    let showWindow: Bool
    let showQuietBadge: Bool
    let automaticallyDownload: Bool
}

enum UpdatePresentationPolicy {
    static func decision(
        for policy: UpdateActionPolicy,
        userInitiated: Bool,
        automaticDownloadConsent: Bool,
        destinationWritable: Bool
    ) -> UpdatePresentationDecision {
        let automaticDownload = policy.allowsAutomaticDownload
            && automaticDownloadConsent
            && destinationWritable
            && policy != .informationOnly
        let quiet = policy == .routine && !userInitiated && !automaticDownload
        return UpdatePresentationDecision(
            showWindow: !quiet && !automaticDownload,
            showQuietBadge: quiet,
            automaticallyDownload: automaticDownload
        )
    }
}

struct UpdateStateMachine: Equatable, Sendable {
    private(set) var phase: UpdatePhase = .idle

    @discardableResult
    mutating func transition(to next: UpdatePhase) -> Bool {
        guard phase != next else { return true }
        guard Self.allowedTransitions[phase, default: []].contains(next) else { return false }
        phase = next
        return true
    }

    static func canRetry(from phase: UpdatePhase) -> Bool {
        phase == .failed || phase == .cancelled || phase == .current || phase == .completed
    }

    private static let allowedTransitions: [UpdatePhase: Set<UpdatePhase>] = [
        .idle: [.permissionRequest, .checking, .available, .downloading, .extracting, .ready, .installing, .completed, .current, .cancelled, .failed],
        .permissionRequest: [.idle, .checking, .failed],
        .checking: [.available, .current, .cancelled, .failed, .idle],
        .available: [.downloading, .extracting, .ready, .installing, .cancelled, .failed, .idle],
        .downloading: [.extracting, .cancelled, .failed, .idle],
        .extracting: [.ready, .installing, .failed, .idle],
        .ready: [.installing, .cancelled, .failed, .idle],
        .installing: [.completed, .failed, .idle],
        .completed: [.checking, .idle],
        .current: [.checking, .idle],
        .cancelled: [.checking, .idle],
        .failed: [.checking, .idle],
    ]
}

enum UpdatePreferenceKey {
    static let channel = "updates.channel"
    static let automaticallyDownloadImportant = "updates.automaticallyDownloadImportant"
}

enum UpdateSettingsPersistence {
    static func channel(from defaults: UserDefaults) -> UpdateChannel {
        defaults.string(forKey: UpdatePreferenceKey.channel)
            .flatMap(UpdateChannel.init(rawValue:)) ?? .stable
    }

    static func save(channel: UpdateChannel, to defaults: UserDefaults) {
        defaults.set(channel.rawValue, forKey: UpdatePreferenceKey.channel)
    }

    static func automaticallyDownloadsImportant(from defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: UpdatePreferenceKey.automaticallyDownloadImportant)
    }

    static func saveAutomaticallyDownloadsImportant(_ enabled: Bool, to defaults: UserDefaults) {
        defaults.set(enabled, forKey: UpdatePreferenceKey.automaticallyDownloadImportant)
    }
}
