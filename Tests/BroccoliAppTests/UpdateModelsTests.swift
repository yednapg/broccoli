import Foundation
import Testing
@testable import BroccoliApp

@Suite("Update policy")
struct UpdateModelsTests {
    @Test func channelsUseRequiredIntervalsAndVisibility() {
        #expect(UpdateChannel.stable.checkInterval == 86_400)
        #expect(UpdateChannel.beta.checkInterval == 21_600)
        #expect(UpdateChannel.stable.allowedSparkleChannels.isEmpty)
        #expect(UpdateChannel.beta.allowedSparkleChannels == ["beta"])
    }

    @Test func priorityParserAcceptsNamespacedAndNestedProperties() {
        #expect(UpdatePriorityParser.parse(
            properties: ["broccoli:priority": "important"],
            isCriticalUpdate: false
        ) == .important)
        #expect(UpdatePriorityParser.parse(
            properties: ["item": ["broccoli:priority": ["content": "critical"]]],
            isCriticalUpdate: false
        ) == .critical)
        #expect(UpdatePriorityParser.parse(
            properties: ["broccoli:priority": "unknown"],
            isCriticalUpdate: false
        ) == .routine)
        #expect(UpdatePriorityParser.parse(properties: [:], isCriticalUpdate: true) == .critical)
    }

    @Test func routineIsQuietOnlyForScheduledChecks() {
        let background = UpdatePresentationPolicy.decision(
            for: .routine,
            userInitiated: false,
            automaticDownloadConsent: true,
            destinationWritable: true
        )
        #expect(background.showQuietBadge)
        #expect(!background.showWindow)
        #expect(!background.automaticallyDownload)

        let manual = UpdatePresentationPolicy.decision(
            for: .routine,
            userInitiated: true,
            automaticDownloadConsent: true,
            destinationWritable: true
        )
        #expect(manual.showWindow)
    }

    @Test func priorityNeverOverridesDownloadConsentOrWritableDestination() {
        for policy in [UpdateActionPolicy.important, .critical] {
            #expect(!UpdatePresentationPolicy.decision(
                for: policy,
                userInitiated: false,
                automaticDownloadConsent: false,
                destinationWritable: true
            ).automaticallyDownload)
            #expect(!UpdatePresentationPolicy.decision(
                for: policy,
                userInitiated: false,
                automaticDownloadConsent: true,
                destinationWritable: false
            ).automaticallyDownload)
            #expect(UpdatePresentationPolicy.decision(
                for: policy,
                userInitiated: false,
                automaticDownloadConsent: true,
                destinationWritable: true
            ).automaticallyDownload)
        }
    }

    @Test func skipAndInformationalPoliciesAreSafe() {
        #expect(UpdateActionPolicy.routine.allowsPermanentSkip)
        #expect(!UpdateActionPolicy.important.allowsPermanentSkip)
        #expect(!UpdateActionPolicy.critical.allowsPermanentSkip)
        #expect(!UpdateActionPolicy.informationOnly.allowsAutomaticDownload)
    }

    @Test func globalBuildEligibilityRejectsEqualLowerAndMalformedBuilds() {
        #expect(UpdateEligibility.isNewerBuild(candidate: "2", installed: "1"))
        #expect(!UpdateEligibility.isNewerBuild(candidate: "1", installed: "1"))
        #expect(!UpdateEligibility.isNewerBuild(candidate: "1", installed: "2"))
        #expect(!UpdateEligibility.isNewerBuild(candidate: "beta", installed: "1"))
        #expect(!UpdateEligibility.isNewerBuild(candidate: "2", installed: "local"))
    }

    @Test func updateSettingsPersistAndMalformedChannelFailsClosedToStable() {
        let suiteName = "UpdateModelsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(UpdateSettingsPersistence.channel(from: defaults) == .stable)
        UpdateSettingsPersistence.save(channel: .beta, to: defaults)
        UpdateSettingsPersistence.saveAutomaticallyDownloadsImportant(true, to: defaults)
        #expect(UpdateSettingsPersistence.channel(from: defaults) == .beta)
        #expect(UpdateSettingsPersistence.automaticallyDownloadsImportant(from: defaults))

        defaults.set("nightly", forKey: UpdatePreferenceKey.channel)
        #expect(UpdateSettingsPersistence.channel(from: defaults) == .stable)
    }

    @Test func updateStateMachineCoversProgressCancellationAndRetry() {
        var machine = UpdateStateMachine()
        let checked = machine.transition(to: .checking)
        let found = machine.transition(to: .available)
        let downloaded = machine.transition(to: .downloading)
        let extracted = machine.transition(to: .extracting)
        let ready = machine.transition(to: .ready)
        let installing = machine.transition(to: .installing)
        let completed = machine.transition(to: .completed)
        let invalidRegression = machine.transition(to: .downloading)
        #expect(checked)
        #expect(found)
        #expect(downloaded)
        #expect(extracted)
        #expect(ready)
        #expect(installing)
        #expect(completed)
        #expect(!invalidRegression)
        #expect(UpdateStateMachine.canRetry(from: .failed))
        #expect(UpdateStateMachine.canRetry(from: .cancelled))
        #expect(!UpdateStateMachine.canRetry(from: .installing))
    }
}
