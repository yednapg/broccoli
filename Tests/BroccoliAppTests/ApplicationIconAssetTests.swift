import AppKit
import XCTest
@testable import BroccoliApp

@MainActor
final class ApplicationIconAssetTests: XCTestCase {
    func testCompiledArtworkFillsTheNativeMaskWithoutAnExtraNeutralFrame() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let developer = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
            ?? "/Applications/Xcode.app/Contents/Developer")
        let tool = developer.deletingLastPathComponent()
            .appendingPathComponent("Applications/Icon Composer.app/Contents/Executables/ictool")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else {
            throw XCTSkip("Icon Composer export requires the supported full-Xcode toolchain")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for rendition in ["Default", "Dark"] {
            let output = directory.appendingPathComponent("\(rendition).png")
            let process = Process()
            process.executableURL = tool
            process.arguments = [root.appendingPathComponent("Support/Broccoli.icon").path,
                "--export-image", "--output-file", output.path, "--platform", "macOS",
                "--rendition", rendition, "--width", "256", "--height", "256", "--scale", "1"]
            process.standardOutput = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: output)))
            // The old padded artwork left a neutral frame here, well inside the system edge.
            let color = try XCTUnwrap(bitmap.colorAt(x: 12, y: 128)?.usingColorSpace(.sRGB))
            XCTAssertGreaterThan(color.alphaComponent, 0.99)
            if rendition == "Default" {
                XCTAssertGreaterThan(color.greenComponent, color.redComponent + 0.06)
                XCTAssertGreaterThan(color.greenComponent, color.blueComponent + 0.02)
            } else {
                XCTAssertLessThan(max(color.redComponent, color.greenComponent, color.blueComponent), 0.16)
            }
        }
    }
}
