public struct AppIdentity: Equatable, Sendable {
    public let displayName: String
    public let bundleIdentifier: String
    public let minimumMacOSVersion: String
    public let shortVersion: String
    public let buildVersion: String

    public init(
        displayName: String,
        bundleIdentifier: String,
        minimumMacOSVersion: String,
        shortVersion: String,
        buildVersion: String
    ) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.minimumMacOSVersion = minimumMacOSVersion
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
    }
}

public extension AppIdentity {
    static let linguistMac = AppIdentity(
        displayName: "LinguistMac",
        bundleIdentifier: "com.peerapatj.LinguistMac",
        minimumMacOSVersion: "15.0",
        shortVersion: "0.1",
        buildVersion: "1"
    )
}
