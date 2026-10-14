import CoreLocation
import Foundation
import GrzybEngine
import Observation

/// GPS position and compass heading; works offline.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var coordinate: Coordinate?
    private(set) var accuracyM: Double?
    private(set) var headingDegrees: Double?
    private(set) var authorization: CLAuthorizationStatus
    private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = 2
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func startHeading() {
        guard CLLocationManager.headingAvailable() else { return }
        manager.startUpdatingHeading()
    }

    func stopHeading() {
        manager.stopUpdatingHeading()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            coordinate = Coordinate(lon: last.coordinate.longitude, lat: last.coordinate.latitude)
            accuracyM = last.horizontalAccuracy
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in headingDegrees = value }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways { self.manager.startUpdatingLocation() }
        }
    }
}
