import Foundation

/// Location for namaz times and the compass for Qibla, injected like `LedgerClient`.
public struct LocationClient: Sendable {
    public struct Place: Sendable, Hashable {
        public var latitude: Double
        public var longitude: Double
        public var city: String?

        public init(latitude: Double, longitude: Double, city: String?) {
            self.latitude = latitude
            self.longitude = longitude
            self.city = city
        }
    }

    /// One fix (asks for permission the first time); throws when not allowed.
    public var currentPlace: @Sendable () async throws -> Place
    /// Starts true-north headings; false when the phone has no compass.
    public var startHeading: @Sendable (@escaping @Sendable (Double) -> Void) -> Bool
    public var stopHeading: @Sendable () -> Void

    public init(currentPlace: @escaping @Sendable () async throws -> Place,
                startHeading: @escaping @Sendable (@escaping @Sendable (Double) -> Void) -> Bool,
                stopHeading: @escaping @Sendable () -> Void) {
        self.currentPlace = currentPlace
        self.startHeading = startHeading
        self.stopHeading = stopHeading
    }

    public static let unavailable = LocationClient(currentPlace: { throw CoreError.notFound }, startHeading: { _ in false }, stopHeading: {})
}
