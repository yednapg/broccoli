import Foundation
import FoundationModels
import BroccoliCore

enum CalculatorIntentInterpreter {
    private static let instructions = """
        You only classify a calculator phrase into fields.
        Copy numbers exactly from the user.
        Never invent numbers.
        Never compute.
        Use kind unknown when unsure.
        """

    private static let session: LanguageModelSession = {
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
        return session
    }()

    @Generable
    struct Draft {
        var kind: String
        var numbers: [Double]
        var source: String
        var target: String
        var operation: String
    }

    static func availabilityLabel() -> String {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            if !model.supportsLocale() {
                return "Not available for this language"
            }
            return "On this Mac"
        case .unavailable(.deviceNotEligible):
            return "Not available on this Mac"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings"
        case .unavailable(.modelNotReady):
            return "Still downloading"
        case .unavailable:
            return "Unavailable"
        }
    }

    static func interpret(_ query: String) async -> String? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability, model.supportsLocale() else {
            return nil
        }

        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                await classify(query)
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(1_500))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private static func classify(_ query: String) async -> String? {
        do {
            let response = try await session.respond(to: query, generating: Draft.self)
            let draft = response.content
            return CalculatorProposalValidator.canonicalQuery(
                kind: draft.kind,
                numbers: draft.numbers,
                source: draft.source,
                target: draft.target,
                operation: draft.operation,
                originalQuery: query
            )
        } catch {
            return nil
        }
    }
}
