@preconcurrency import AppKit
import CryptoKit
import Foundation

/// Identifies one persisted bitmap.
///
/// The drawing context is part of the identity because artwork is materialized per
/// appearance, contrast, point size and display scale. `validityToken` carries the source's
/// own version — a bundle's modification date, or the running OS build for system-vended
/// content-type artwork — so an updated application or a macOS upgrade invalidates its
/// entries instead of pinning stale pixels.
struct NativeIconDiskCacheKey: Hashable, Sendable {
    let source: String
    let validityToken: String
    let appearance: String
    let increasesContrast: Bool
    let pointSize: CGFloat
    let backingScale: CGFloat

    var fileName: String {
        let descriptor = [
            source,
            validityToken,
            NativeIconDiskCache.operatingSystemToken,
            appearance,
            increasesContrast ? "contrast" : "standard",
            String(format: "%.2f", pointSize),
            String(format: "%.2f", backingScale),
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(descriptor.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".png"
    }
}

/// Persists materialized native artwork between launches.
///
/// Icon Services is only slow the first time a process asks for a given application or
/// Settings pane; later requests in the same process are served from its own cache. That is
/// why the launcher felt slow at first launch and after a quit, then felt fine. Keeping the
/// finished bitmap on disk moves that first cost off the launch path entirely.
///
/// Only fully resolved artwork is written. A generic Icon Services placeholder must never be
/// persisted, or the wrong icon would survive every future launch.
final class NativeIconDiskCache: @unchecked Sendable {
    static let shared = NativeIconDiskCache()
    /// Roughly an installed application catalog across two appearances. Small enough that the
    /// directory stays a few megabytes of 80-pixel PNGs.
    static let entryLimit = 768

    static let operatingSystemToken: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }()

    private let directory: URL?
    private let lock = NSLock()
    private var hasPruned = false

    init(directory: URL? = NativeIconDiskCache.defaultDirectory()) {
        self.directory = directory
    }

    static func defaultDirectory() -> URL? {
        guard let base = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let directory = base
            .appendingPathComponent("dev.gauravpandey.broccoli", isDirectory: true)
            .appendingPathComponent("NativeIcons", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }
        return directory
    }

    /// A bundle's modification date. Absent metadata yields `nil`, which disables persistence
    /// for that source rather than caching something we cannot invalidate.
    static func key(forFileAt url: URL, context: IconRenderContext) -> NativeIconDiskCacheKey? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let modifiedAt = values?.contentModificationDate else { return nil }
        return NativeIconDiskCacheKey(
            source: url.standardizedFileURL.path,
            validityToken: String(Int(modifiedAt.timeIntervalSince1970)),
            appearance: context.appearance.rawValue,
            increasesContrast: context.increasesContrast,
            pointSize: context.pointSize,
            backingScale: context.backingScale
        )
    }

    static func key(
        forContentTypeIdentifier identifier: String,
        context: IconRenderContext
    ) -> NativeIconDiskCacheKey {
        NativeIconDiskCacheKey(
            source: "uti:" + identifier,
            validityToken: operatingSystemToken,
            appearance: context.appearance.rawValue,
            increasesContrast: context.increasesContrast,
            pointSize: context.pointSize,
            backingScale: context.backingScale
        )
    }

    func icon(for key: NativeIconDiskCacheKey, pointSize: CGFloat) -> MaterializedSystemSettingsIcon? {
        guard let url = directory?.appendingPathComponent(key.fileName) else { return nil }
        return autoreleasepool {
            guard let data = try? Data(contentsOf: url),
                  let stored = NSBitmapImageRep(data: data),
                  let decoded = stored.cgImage else { return nil }
            // Rebuild an unpacked bitmap so pixel geometry and cost are exactly what the
            // in-memory cache accounts for, independent of how the PNG was encoded.
            let pixels = max(1, stored.pixelsWide)
            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixels,
                pixelsHigh: pixels,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: [],
                bytesPerRow: 0,
                bitsPerPixel: 0
            ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
            let rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
            context.cgContext.clear(rect)
            context.cgContext.draw(decoded, in: rect)
            context.flushGraphics()
            bitmap.size = NSSize(width: pointSize, height: pointSize)

            let image = NSImage(size: bitmap.size)
            image.addRepresentation(bitmap)
            image.isTemplate = false
            return MaterializedSystemSettingsIcon(image: image, bitmap: bitmap)
        }
    }

    func store(_ icon: MaterializedSystemSettingsIcon, for key: NativeIconDiskCacheKey) {
        guard !icon.isProvisional, let directory else { return }
        autoreleasepool {
            guard let bitmap = icon.image.representations.first as? NSBitmapImageRep,
                  let data = bitmap.representation(using: .png, properties: [:]) else { return }
            try? data.write(to: directory.appendingPathComponent(key.fileName), options: .atomic)
        }
        pruneIfNeeded(in: directory)
    }

    /// One bounded sweep per process. The directory only grows when the user installs
    /// applications or changes appearance, so continuous bookkeeping is not warranted.
    private func pruneIfNeeded(in directory: URL) {
        lock.lock()
        if hasPruned {
            lock.unlock()
            return
        }
        hasPruned = true
        lock.unlock()

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ), entries.count > Self.entryLimit else { return }
        let dated = entries.map { url -> (URL, Date) in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return (url, values?.contentModificationDate ?? .distantPast)
        }.sorted { $0.1 < $1.1 }
        for (url, _) in dated.prefix(dated.count - Self.entryLimit) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
