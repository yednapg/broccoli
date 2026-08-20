import Foundation

public enum ApplicationDiscoveryPolicy {
    private static let finderPath = "/System/Library/CoreServices/Finder.app"
    private static let explicitlyAllowedSystemApplications: Set<String> = [finderPath]

    public static func isCandidatePath(_ path: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        if explicitlyAllowedSystemApplications.contains(standardized) {
            return true
        }
        if standardized.hasPrefix("/System/Library/")
            || standardized.hasPrefix("/Library/")
            || standardized.hasPrefix("/usr/")
            || standardized.hasPrefix("/private/")
            || standardized.contains("/.Trash/") {
            return false
        }
        let embeddedHelperLocations = [
            "/Contents/Frameworks/",
            "/Contents/Helpers/",
            "/Contents/Library/",
            "/Contents/PlugIns/",
            "/Contents/Resources/",
            "/Contents/XPCServices/",
            ".framework/",
        ]
        return !embeddedHelperLocations.contains { standardized.contains($0) }
    }

    public static func isSupportedApplicationBundle(
        path: String,
        packageType: String?,
        bundleIdentifier: String?
    ) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        if standardized == finderPath {
            return packageType == "FNDR" && bundleIdentifier == "com.apple.finder"
        }
        return packageType == "APPL"
    }

    public static func isUserFacingLocation(
        _ path: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let homeApplications = homeDirectory
            .appendingPathComponent("Applications")
            .standardizedFileURL.path
        return path.hasPrefix("/Applications/")
            || path.hasPrefix("/System/Applications/")
            || path == homeApplications
            || path.hasPrefix(homeApplications + "/")
    }
}
