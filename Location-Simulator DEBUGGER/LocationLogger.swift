import Combine
import CoreLocation
import Foundation
import UIKit

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let sessionID: String
    let recordType: String
    let event: String
    let latitude: Double?
    let longitude: Double?
    let horizontalAccuracy: Double?
    let altitude: Double?
    let speed: Double?
    let course: Double?
    let sourceInformationAvailable: Bool?
    let simulatedBySoftware: Bool?
    let producedByAccessory: Bool?
    let distanceFromBaseline: Double?
    let deviceModel: String
    let iOSVersion: String
    let appVersion: String

    init(
        location: CLLocation,
        sessionID: String,
        baseline: CLLocation?,
        deviceModel: String,
        iOSVersion: String,
        appVersion: String
    ) {
        let source = location.sourceInformation
        self.timestamp = location.timestamp
        self.sessionID = sessionID
        self.recordType = "location"
        self.event = ""
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.horizontalAccuracy = location.horizontalAccuracy
        self.altitude = location.altitude
        self.speed = location.speed >= 0 ? location.speed : nil
        self.course = location.course >= 0 ? location.course : nil
        self.sourceInformationAvailable = source != nil
        self.simulatedBySoftware = source?.isSimulatedBySoftware
        self.producedByAccessory = source?.isProducedByAccessory
        self.distanceFromBaseline = baseline.map { $0.distance(from: location) }
        self.deviceModel = deviceModel
        self.iOSVersion = iOSVersion
        self.appVersion = appVersion
    }

    init(
        event: String,
        sessionID: String,
        location: CLLocation?,
        baseline: CLLocation?,
        deviceModel: String,
        iOSVersion: String,
        appVersion: String
    ) {
        let source = location?.sourceInformation
        self.timestamp = Date()
        self.sessionID = sessionID
        self.recordType = "event"
        self.event = event
        self.latitude = location?.coordinate.latitude
        self.longitude = location?.coordinate.longitude
        self.horizontalAccuracy = location?.horizontalAccuracy
        self.altitude = location?.altitude
        self.speed = location.flatMap { $0.speed >= 0 ? $0.speed : nil }
        self.course = location.flatMap { $0.course >= 0 ? $0.course : nil }
        self.sourceInformationAvailable = source.map { _ in true } ?? location.map { _ in false }
        self.simulatedBySoftware = source?.isSimulatedBySoftware
        self.producedByAccessory = source?.isProducedByAccessory
        self.distanceFromBaseline = location.flatMap { current in
            baseline.map { $0.distance(from: current) }
        }
        self.deviceModel = deviceModel
        self.iOSVersion = iOSVersion
        self.appVersion = appVersion
    }

    var displayText: String {
        let time = Self.timestampString(timestamp)

        if recordType == "event" {
            var lines = [time, "EVENT: \(event)"]
            if let latitude, let longitude {
                lines.append("at \(Self.number(latitude, decimals: 6)), \(Self.number(longitude, decimals: 6))")
            }
            return lines.joined(separator: "\n")
        }

        let lat = latitude.map { Self.number($0, decimals: 6) } ?? "—"
        let lon = longitude.map { Self.number($0, decimals: 6) } ?? "—"
        let accuracy = horizontalAccuracy.map { Self.number($0, decimals: 1) + " m" } ?? "—"
        let distance = distanceFromBaseline.map { Self.number($0, decimals: 1) + " m" } ?? "baseline not set"
        let sourceLine: String

        if sourceInformationAvailable == false {
            sourceLine = "source info: unavailable (nil)"
        } else if sourceInformationAvailable == true {
            sourceLine = "simulatedBySoftware: \(simulatedBySoftware ?? false) | producedByAccessory: \(producedByAccessory ?? false)"
        } else {
            sourceLine = "source info: unknown"
        }

        return [
            time,
            "lat \(lat), lon \(lon)",
            "h-accuracy: \(accuracy)",
            "distance from baseline: \(distance)",
            sourceLine
        ].joined(separator: "\n")
    }

    var csvLine: String {
        var values: [String?] = []
        values.append(Self.timestampString(timestamp))
        values.append(sessionID)
        values.append(recordType)
        values.append(event)
        values.append(latitude.map { String($0) })
        values.append(longitude.map { String($0) })
        values.append(horizontalAccuracy.map { String($0) })
        values.append(altitude.map { String($0) })
        values.append(speed.map { String($0) })
        values.append(course.map { String($0) })
        values.append(sourceInformationAvailable.map { $0 ? "true" : "false" })
        values.append(simulatedBySoftware.map { $0 ? "true" : "false" })
        values.append(producedByAccessory.map { $0 ? "true" : "false" })
        values.append(distanceFromBaseline.map { String($0) })
        values.append(deviceModel)
        values.append(iOSVersion)
        values.append(appVersion)

        let escapedValues = values.map { value -> String in
            guard let value else { return "" }
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return escapedValues.joined(separator: ",")
    }

    static let csvHeader = [
        "timestamp_iso8601",
        "session_id",
        "record_type",
        "event",
        "latitude",
        "longitude",
        "horizontal_accuracy_m",
        "altitude_m",
        "speed_mps",
        "course_degrees",
        "source_information_available",
        "simulated_by_software",
        "produced_by_accessory",
        "distance_from_baseline_m",
        "device_model",
        "ios_version",
        "app_version"
    ].joined(separator: ",")

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func timestampString(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static func number(_ value: Double, decimals: Int) -> String {
        String(
            format: "%.\(decimals)f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }

    private static func boolString(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private static func csvField(_ value: String?) -> String {
        guard let value else { return "" }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

final class LocationLogger: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var entries: [LogEntry] = []
    @Published private(set) var status = "Idle"
    @Published private(set) var isRunning = false
    @Published private(set) var fixCount = 0

    private let manager = CLLocationManager()
    private let maxEntries = 10_000
    private var sessionID = ""
    private var lastLocation: CLLocation?
    private var baselineLocation: CLLocation?

    private let deviceModel = UIDevice.current.model
    private let iOSVersion = UIDevice.current.systemVersion
    private let appVersion: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        return "\(version) (\(build))"
    }()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    var permissionSummary: String {
        let authorization: String
        switch manager.authorizationStatus {
        case .notDetermined:
            authorization = "not requested"
        case .restricted:
            authorization = "restricted"
        case .denied:
            authorization = "denied"
        case .authorizedWhenInUse:
            authorization = "While Using"
        case .authorizedAlways:
            authorization = "Always"
        @unknown default:
            authorization = "unknown"
        }

        let precision = manager.accuracyAuthorization == .fullAccuracy ? "Precise" : "Reduced accuracy"
        return "\(authorization) · \(precision)"
    }

    var locationServicesSummary: String {
        CLLocationManager.locationServicesEnabled() ? "Location Services on" : "Location Services off"
    }

    var deviceSummary: String {
        "\(deviceModel) · iOS \(iOSVersion) · app \(appVersion)"
    }

    var baselineSummary: String {
        guard let baselineLocation else { return "not set" }
        let lat = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), baselineLocation.coordinate.latitude)
        let lon = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), baselineLocation.coordinate.longitude)
        return "\(lat), \(lon)"
    }

    var maximumDisplacementSummary: String {
        guard !sessionID.isEmpty else { return "—" }
        let maximum = entries
            .filter { $0.sessionID == sessionID && $0.recordType == "location" }
            .compactMap(\.distanceFromBaseline)
            .max()
        guard let maximum else { return "—" }
        return String(format: "%.0f m", locale: Locale(identifier: "en_US_POSIX"), maximum)
    }

    var csvText: String {
        ([LogEntry.csvHeader] + entries.reversed().map(\.csvLine)).joined(separator: "\n")
    }

    var exportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "location-session-\(formatter.string(from: Date()))"
    }

    func start() {
        guard !isRunning else { return }

        sessionID = UUID().uuidString
        baselineLocation = nil
        fixCount = 0
        isRunning = true
        appendEvent("session_started")

        guard CLLocationManager.locationServicesEnabled() else {
            isRunning = false
            status = "Location Services are off"
            appendEvent("location_services_off")
            return
        }

        applyAuthorization()
    }

    func stop() {
        guard isRunning else { return }
        manager.stopUpdatingLocation()
        appendEvent("session_stopped")
        isRunning = false
        status = "Stopped · \(fixCount) fixes"
    }

    func setBaseline() {
        guard let lastLocation else {
            status = "Waiting for a location fix before setting baseline"
            return
        }
        baselineLocation = lastLocation
        appendEvent("baseline_set")
        status = "Baseline set · \(fixCount) fixes"
    }

    func mark(_ event: String) {
        guard isRunning else { return }
        appendEvent(event)
    }

    func clearLog() {
        guard !isRunning else { return }
        entries.removeAll()
        baselineLocation = nil
        lastLocation = nil
        fixCount = 0
        status = "Log cleared"
    }

    func reportExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            status = "CSV export ready"
        case .failure(let error):
            status = "Export failed: \(error.localizedDescription)"
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        applyAuthorization()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            lastLocation = location
            fixCount += 1
            append(LogEntry(
                location: location,
                sessionID: sessionID,
                baseline: baselineLocation,
                deviceModel: deviceModel,
                iOSVersion: iOSVersion,
                appVersion: appVersion
            ))
        }

        if isRunning {
            status = "Running · \(fixCount) fixes · \(permissionSummary)"
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "Location error: \(error.localizedDescription)"
        appendEvent("location_error: \(error.localizedDescription)")
    }

    private func applyAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            status = isRunning ? "Waiting for location permission…" : "Idle"
            if isRunning {
                manager.requestWhenInUseAuthorization()
            }
        case .restricted:
            isRunning = false
            manager.stopUpdatingLocation()
            status = "Location access is restricted"
            appendEvent("location_access_restricted")
        case .denied:
            isRunning = false
            manager.stopUpdatingLocation()
            status = "Location permission denied"
            appendEvent("location_permission_denied")
        case .authorizedWhenInUse, .authorizedAlways:
            if isRunning {
                status = "Running · \(permissionSummary)"
                manager.startUpdatingLocation()
            }
        @unknown default:
            isRunning = false
            manager.stopUpdatingLocation()
            status = "Unknown authorization state"
        }
    }

    private func appendEvent(_ event: String) {
        append(LogEntry(
            event: event,
            sessionID: sessionID,
            location: lastLocation,
            baseline: baselineLocation,
            deviceModel: deviceModel,
            iOSVersion: iOSVersion,
            appVersion: appVersion
        ))
    }

    private func append(_ entry: LogEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }
}

