import CoreLocation
import Foundation

/// Where the phone is, for namaz times, and which way it points, for the Qibla compass. When-in-use only;
/// the place is kept on the phone and never sent anywhere (reverse geocoding uses Apple's service for the city name).
public final class LocationService: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    public struct Place: Sendable, Codable, Hashable {
        public var latitude: Double
        public var longitude: Double
        public var city: String?
        public var timeZoneID: String
    }

    public enum Failure: Error { case notAllowed, unavailable }

    public static let shared = LocationService()

    private let manager = CLLocationManager()
    private let lock = NSLock()
    private var authorization: CheckedContinuation<Void, Never>?
    private var headingHandler: (@Sendable (Double) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.headingFilter = 1
    }

    /// One fix, asking for permission the first time.
    public func currentPlace() async throws -> Place {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                lock.withLock { authorization = continuation }
                manager.requestWhenInUseAuthorization()
            }
        }
        #if os(iOS)
        let allowed: [CLAuthorizationStatus] = [.authorizedWhenInUse, .authorizedAlways]
        #else
        let allowed: [CLAuthorizationStatus] = [.authorizedAlways]
        #endif
        guard allowed.contains(manager.authorizationStatus) else { throw Failure.notAllowed }
        // No fix within 20 seconds (indoors, no signal): give up rather than spin forever.
        return try await withThrowingTaskGroup(of: Place.self) { group in
            group.addTask { try await self.firstPlace() }
            group.addTask {
                try await Task.sleep(for: .seconds(20))
                throw Failure.unavailable
            }
            defer { group.cancelAll() }
            guard let place = try await group.next() else { throw Failure.unavailable }
            return place
        }
    }

    private func firstPlace() async throws -> Place {
        for try await update in CLLocationUpdate.liveUpdates() {
            guard let location = update.location else {
                if update.authorizationDenied { throw Failure.notAllowed }
                continue
            }
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            let city = [placemark?.locality, placemark?.country].compactMap { $0 }.joined(separator: ", ")
            return Place(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                         city: city.isEmpty ? nil : city, timeZoneID: placemark?.timeZone?.identifier ?? TimeZone.current.identifier)
        }
        throw Failure.unavailable
    }

    /// True-north heading in degrees, as the phone turns; nil when the phone has no compass.
    public func startHeading(_ handler: @escaping @Sendable (Double) -> Void) -> Bool {
        #if os(iOS)
        guard CLLocationManager.headingAvailable() else { return false }
        lock.withLock { headingHandler = handler }
        // True north needs a location fix; without one iOS reports only magnetic headings.
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        return true
        #else
        return false
        #endif
    }

    public func stopHeading() {
        #if os(iOS)
        manager.stopUpdatingHeading()
        manager.stopUpdatingLocation()
        #endif
        lock.withLock { headingHandler = nil }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { authorization = nil }
            return authorization
        }
        waiting?.resume()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        let handler = lock.withLock { headingHandler }
        handler?(value)
    }
}
