/// Version information shown in the app and recorded in BUILD_HISTORY.
public struct AppInfo: Sendable, Equatable {
    public let marketingVersion: String
    public let buildNumber: String

    public init(marketingVersion: String, buildNumber: String) {
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
    }

    /// "0.0.1 (1)"
    public var displayVersion: String { "\(marketingVersion) (\(buildNumber))" }

    /// Reads CFBundleShortVersionString / CFBundleVersion from an Info.plist dictionary.
    public init(infoDictionary: [String: Any]?) {
        let info = infoDictionary ?? [:]
        self.init(
            marketingVersion: info["CFBundleShortVersionString"] as? String ?? "0.0.0",
            buildNumber: info["CFBundleVersion"] as? String ?? "0"
        )
    }
}
