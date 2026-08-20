import Foundation
import XCTest
@testable import BroccoliCore

final class ApplicationCatalogDeltaTests: XCTestCase {
    func testIdenticalUpsertDoesNotReportAChange() {
        let existing = application("/Applications/Notes.app", name: "Notes")

        let delta = ApplicationCatalogDelta.applying(
            upserts: [existing],
            to: [existing]
        )

        XCTAssertFalse(delta.hasChanges)
        XCTAssertEqual(delta.snapshot, [existing])
        XCTAssertTrue(delta.added.isEmpty)
        XCTAssertTrue(delta.changed.isEmpty)
        XCTAssertTrue(delta.removed.isEmpty)
    }

    func testApplyingAddChangeAndRemoveProducesFocusedDelta() {
        let originalEditor = application(
            "/Applications/Editor.app",
            identifier: "com.example.editor",
            name: "Editor"
        )
        let removedMail = application("/Applications/Mailbox.app", name: "Mailbox")
        let changedEditor = application(
            "/Applications/Editor.app",
            identifier: "com.example.editor",
            name: "Editor Pro"
        )
        let addedCalendar = application("/Applications/Calendar.app", name: "Calendar")

        let delta = ApplicationCatalogDelta.applying(
            upserts: [changedEditor, addedCalendar],
            removingPaths: [removedMail.path],
            to: [originalEditor, removedMail]
        )

        XCTAssertTrue(delta.hasChanges)
        XCTAssertEqual(delta.added, [addedCalendar])
        XCTAssertEqual(delta.changed, [changedEditor])
        XCTAssertEqual(delta.removed, [removedMail])
        XCTAssertEqual(delta.snapshot, [addedCalendar, changedEditor])
    }

    func testMountedVolumeContainmentUsesPathComponentBoundaries() {
        let volume = URL(fileURLWithPath: "/Volumes/Work")
        let contained = application("/Volumes/Work/Applications/Editor.app", name: "Editor")
        let standardizedContained = application(
            "/Volumes/Work/Applications/../Utilities/Monitor.app",
            name: "Monitor"
        )
        let similarPrefix = application(
            "/Volumes/Workspace/Applications/Calendar.app",
            name: "Calendar"
        )

        XCTAssertTrue(ApplicationCatalogDelta.isPath(
            contained.path,
            containedInVolumeAt: volume
        ))
        XCTAssertTrue(ApplicationCatalogDelta.isPath(
            standardizedContained.path,
            containedInVolumeAt: volume
        ))
        XCTAssertFalse(ApplicationCatalogDelta.isPath(
            similarPrefix.path,
            containedInVolumeAt: volume
        ))
        XCTAssertEqual(
            ApplicationCatalogDelta.paths(
                in: [similarPrefix, contained, standardizedContained],
                containedInVolumeAt: volume
            ),
            Set([contained.path, standardizedContained.path])
        )
    }

    func testSnapshotAndDeltaOrderingAreDeterministic() {
        let alphaB = application("/Applications/B/Alpha.app", name: "Alpha")
        let beta = application("/Applications/Beta.app", name: "beta")
        let alphaA = application("/Applications/A/Alpha.app", name: "Alpha")
        let expected = [alphaA, alphaB, beta]

        let forward = ApplicationCatalogDelta.applying(
            upserts: [beta, alphaB, alphaA],
            to: []
        )
        let reverse = ApplicationCatalogDelta.applying(
            upserts: [alphaA, alphaB, beta],
            to: []
        )

        XCTAssertEqual(forward.snapshot, expected)
        XCTAssertEqual(forward.added, expected)
        XCTAssertEqual(reverse.snapshot, expected)
        XCTAssertEqual(reverse.added, expected)
    }

    private func application(
        _ path: String,
        identifier: String? = nil,
        name: String
    ) -> CachedApplication {
        CachedApplication(
            path: path,
            bundleIdentifier: identifier,
            displayName: name,
            modifiedAt: nil
        )
    }
}
