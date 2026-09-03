@preconcurrency import AppKit
import SwiftUI

@MainActor
final class BroccoliUpdateWindowController: NSWindowController, NSWindowDelegate {
    private var closesProgrammatically = false
    private let onUserClose: () -> Void

    init(coordinator: UpdateCoordinator, onUserClose: @escaping () -> Void) {
        self.onUserClose = onUserClose
        let rootView = BroccoliUpdateView(coordinator: coordinator)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Broccoli Update"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 470))
        window.minSize = NSSize(width: 520, height: 420)
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func closeWithoutCallback() {
        closesProgrammatically = true
        close()
        closesProgrammatically = false
    }

    func windowWillClose(_ notification: Notification) {
        guard !closesProgrammatically else { return }
        onUserClose()
    }
}

private struct BroccoliUpdateView: View {
    @Bindable var coordinator: UpdateCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 23, weight: .semibold))
                    Text(coordinator.statusMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            if coordinator.phase == .permissionRequest {
                permissionContent
            } else {
                updateContent
            }

            Spacer(minLength: 4)
            Divider()
            actionBar
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 420)
        .background(.regularMaterial)
    }

    private var title: String {
        switch coordinator.phase {
        case .permissionRequest: "Keep Broccoli up to date"
        case .available: coordinator.candidate?.title ?? "Update available"
        case .ready: "Ready to update"
        case .completed: "Broccoli was updated"
        case .current: "You’re up to date"
        case .failed: "Update problem"
        default: "Updating Broccoli"
        }
    }

    private var permissionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Broccoli can check its signed update feed automatically. No system profile, analytics, searches, or other telemetry is sent.")
            Toggle(
                "Automatically download important and critical updates",
                isOn: $coordinator.automaticallyDownloadsImportantUpdates
            )
            Text("Installation and relaunch always require your choice.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var updateContent: some View {
        if let candidate = coordinator.candidate, coordinator.phase == .available {
            HStack {
                Label("Version \(candidate.version) (\(candidate.build))", systemImage: "shippingbox")
                Spacer()
                Text(candidate.priority.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(priorityColor(candidate.priority).opacity(0.16), in: Capsule())
            }
        }

        if let progress = coordinator.downloadProgress,
           coordinator.phase == .downloading || coordinator.phase == .extracting {
            ProgressView(value: progress)
        } else if coordinator.phase == .checking || coordinator.phase == .extracting || coordinator.phase == .installing {
            ProgressView().controlSize(.small)
        }

        if let error = coordinator.errorMessage, !error.isEmpty {
            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(coordinator.phase == .failed ? .red : .secondary)
                .textSelection(.enabled)
        }

        if let notes = coordinator.releaseNotes, !notes.isEmpty {
            GroupBox("Release Notes") {
                ScrollView {
                    Text(notes)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 110)
            }
        } else if coordinator.phase == .available {
            Text("Release notes are not available for this update.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        HStack {
            switch coordinator.phase {
            case .permissionRequest:
                Button("Not Now") { coordinator.allowAutomaticChecks(false) }
                Spacer()
                Button("Allow Automatic Checks") { coordinator.allowAutomaticChecks(true) }
                    .buttonStyle(.borderedProminent)
            case .checking, .downloading:
                Spacer()
                Button("Cancel") { coordinator.cancelCurrentOperation() }
            case .available:
                availableActions
            case .ready:
                Button("Later") { coordinator.chooseLater() }
                Spacer()
                Button("Install and Relaunch") { coordinator.installAndRelaunch() }
                    .buttonStyle(.borderedProminent)
            case .installing:
                Spacer()
                Button("Try Quitting Again") { coordinator.retryTermination() }
            case .current, .completed, .cancelled, .failed:
                Spacer()
                if coordinator.phase == .failed {
                    Button("Check Again") { coordinator.retryUpdate() }
                }
                Button("Done") { coordinator.acknowledge() }
                    .keyboardShortcut(.defaultAction)
            case .idle, .extracting:
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var availableActions: some View {
        if coordinator.candidate?.isInformationalOnly == true {
            Button("Later") { coordinator.chooseLater() }
            Spacer()
            Button("Learn More") { coordinator.openInformationPage() }
                .buttonStyle(.borderedProminent)
        } else {
            if UpdateActionPolicy(
                priority: coordinator.candidate?.priority ?? .routine,
                isCritical: coordinator.candidate?.isCritical ?? false,
                isInformationalOnly: false
            ).allowsPermanentSkip {
                Button("Skip This Version") { coordinator.skipVersion() }
            }
            Button("Later") { coordinator.chooseLater() }
            Spacer()
            Button("Download and Install") { coordinator.downloadAndInstall() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func priorityColor(_ priority: UpdatePriority) -> Color {
        switch priority {
        case .routine: .secondary
        case .important: .orange
        case .critical: .red
        }
    }
}
