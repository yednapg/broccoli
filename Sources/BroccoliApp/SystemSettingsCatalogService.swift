import BroccoliCore
import Foundation

enum SystemSettingsCatalogDiscovery {
    static let settingsExtensionPoint = "com.apple.Settings.extension.ui"

    nonisolated static func discover(
        roots: [URL] = SystemSettingsExtensionIndex.standardRoots
    ) -> [SearchEntry] {
        let panes = roots
            .flatMap(extensionURLs)
            .compactMap(pane)
        return SettingsCatalog.searchEntries(from: panes)
    }

    nonisolated static func pane(at extensionURL: URL) -> SystemSettingsPane? {
        guard let bundle = Bundle(url: extensionURL),
              let bundleIdentifier = bundle.bundleIdentifier,
              extensionPoint(in: bundle.infoDictionary) == settingsExtensionPoint else {
            return nil
        }

        let title = localizedTitle(in: bundle)
        guard !title.isEmpty else { return nil }
        let route = "x-apple.systempreferences:\(bundleIdentifier)"
        let terms = searchTerms(in: bundle)
        return SystemSettingsPane(
            bundleIdentifier: bundleIdentifier,
            title: title,
            route: route,
            searchTerms: terms
        )
    }

    nonisolated static func searchTerms(in bundle: Bundle) -> [SystemSettingsSearchTerm] {
        guard let fileName = searchTermsFileName(in: bundle.infoDictionary),
              let url = bundle.url(forResource: fileName, withExtension: "searchTerms"),
              let data = try? Data(contentsOf: url),
              let propertyList = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) else { return [] }

        return searchTerms(in: propertyList)
    }

    nonisolated static func searchTerms(in propertyList: Any) -> [SystemSettingsSearchTerm] {
        guard let groups = propertyList as? [String: Any] else { return [] }
        return groups.keys.sorted().flatMap { destination -> [SystemSettingsSearchTerm] in
            guard let group = groups[destination] as? [String: Any],
                  let strings = group["localizableStrings"] as? [[String: Any]] else { return [] }
            return strings.enumerated().compactMap { offset, value in
                guard let title = value["title"] as? String else { return nil }
                let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedTitle.isEmpty else { return nil }
                let keywords = (value["index"] as? String)?
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty } ?? []
                return SystemSettingsSearchTerm(
                    id: "\(destination):\(offset)",
                    destination: destination,
                    title: trimmedTitle,
                    keywords: keywords
                )
            }
        }
    }

    nonisolated private static func extensionURLs(in root: URL) -> [URL] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return children.filter { $0.pathExtension == "appex" }
    }

    nonisolated private static func localizedTitle(in bundle: Bundle) -> String {
        (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? ""
    }

    nonisolated private static func extensionPoint(in info: [String: Any]?) -> String? {
        if let attributes = info?["EXAppExtensionAttributes"] as? [String: Any],
           let identifier = attributes["EXExtensionPointIdentifier"] as? String {
            return identifier
        }
        return (info?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String
    }

    nonisolated private static func searchTermsFileName(in info: [String: Any]?) -> String? {
        if let attributes = info?["EXAppExtensionAttributes"] as? [String: Any],
           let settings = attributes["SettingsExtensionAttributes"] as? [String: Any],
           let fileName = settings["searchTermsFileName"] as? String {
            return fileName
        }
        if let extensionDictionary = info?["NSExtension"] as? [String: Any],
           let attributes = extensionDictionary["NSExtensionAttributes"] as? [String: Any],
           let fileName = attributes["searchTermsFileName"] as? String {
            return fileName
        }
        return nil
    }
}

@MainActor
final class SystemSettingsCatalogService {
    private var discoveryTask: Task<Void, Never>?
    var onCatalogChanged: (([SearchEntry]) -> Void)?

    func start() {
        guard discoveryTask == nil else { return }
        discoveryTask = Task { [weak self] in
            let entries = await Task.detached(priority: .utility) {
                SystemSettingsCatalogDiscovery.discover()
            }.value
            guard !Task.isCancelled, let self else { return }
            discoveryTask = nil
            onCatalogChanged?(entries)
        }
    }

    func refresh() {
        discoveryTask?.cancel()
        discoveryTask = nil
        start()
    }
}
