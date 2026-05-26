//
//  RemoteOrDirectClient.swift
//  LukaMini
//

import Dexcom
import Foundation
import OSLog

struct RemoteOrDirectClient {
    private static let backendURL = URL(string: "https://luka-vapor-v2.fly.dev")!
    private static let logger = Logger(subsystem: "com.kylebashour.GlimpseMini", category: "RemoteOrDirectClient")

    let username: String
    let password: String
    let direct: DexcomClient

    init(username: String, password: String, accountLocation: AccountLocation) {
        self.username = username
        self.password = password
        self.direct = DexcomClient(
            username: username,
            password: password,
            accountLocation: accountLocation
        )
    }

    /// Whether to consult the Luka server before falling back to Dexcom.
    /// Read live so toggling the setting takes effect on the next refresh.
    /// Defaults to `true` when the user hasn't set a preference.
    private var useServer: Bool {
        UserDefaults.standard.object(forKey: .useServerForReadingsKey) as? Bool ?? true
    }

    func getGlucoseReadings(duration: Measurement<UnitDuration>) async throws -> [GlucoseReading] {
        guard useServer else {
            return try await direct.getGlucoseReadings(duration: duration)
        }

        do {
            if let cached = try await fetchFromBackend(duration: duration) {
                Self.logger.info("Served \(cached.count) readings from luka-vapor cache")
                return cached
            }
            Self.logger.info("No cached session on luka-vapor, falling back to Dexcom")
        } catch {
            Self.logger.error("luka-vapor request failed, falling back to Dexcom: \(error.localizedDescription, privacy: .public)")
        }
        return try await direct.getGlucoseReadings(duration: duration)
    }

    private func fetchFromBackend(duration: Measurement<UnitDuration>) async throws -> [GlucoseReading]? {
        let minutes = Int(duration.converted(to: .minutes).value)
        var components = URLComponents(url: Self.backendURL.appendingPathComponent("glucose-readings"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "minutes", value: String(minutes)),
            URLQueryItem(name: "maxCount", value: "288"),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"

        let credentials = "\(username):\(password)"
        guard let credentialsData = credentials.data(using: .utf8) else { return nil }
        request.setValue("Basic \(credentialsData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        Self.logger.debug("Requesting cached readings (minutes=\(minutes, privacy: .public))")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            Self.logger.error("luka-vapor network error: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        guard let http = response as? HTTPURLResponse else {
            Self.logger.error("luka-vapor non-HTTP response")
            throw URLError(.badServerResponse)
        }

        switch http.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([GlucoseReading].self, from: data)
        case 404:
            return nil
        default:
            Self.logger.error("luka-vapor returned unexpected status \(http.statusCode, privacy: .public)")
            throw URLError(.badServerResponse)
        }
    }
}
