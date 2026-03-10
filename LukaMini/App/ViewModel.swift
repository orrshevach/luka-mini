//
//  ViewModel.swift
//  LukaMini
//
//  Created by Kyle Bashour on 4/11/24.
//

import SwiftUI
import Dexcom
import KeychainAccess
import Network

@MainActor @Observable class ViewModel {
    enum State {
        case initial
        case loaded(GlucoseReading)
        case noRecentReading
        case error(Error)
    }

    var isLoggedIn: Bool {
        username != nil && password != nil && location != nil
    }

    private(set) var reading: State = .initial
    private(set) var message: String?
    private(set) var readings: [LiveActivityState.Reading] = []

    @ObservationIgnored private(set) var username: String? = Keychain.standard[.usernameKey]
    @ObservationIgnored private(set) var password: String? = Keychain.standard[.passwordKey]
    @ObservationIgnored private(set) var location: String? = UserDefaults.standard.string(forKey: .locationKey)

    private var client: DexcomClient?
    private let decoder = JSONDecoder()
    private let networkMonitor = NWPathMonitor()
    private var hasNetwork = false

    private var shouldRefreshReading: Bool {
        switch reading {
        case .initial, .error, .noRecentReading:
            return true
        case .loaded(let reading):
            return reading.date.timeIntervalSinceNow < -60 * 5
        }
    }

    init() {
        decoder.dateDecodingStrategy = .iso8601
        setUpClientAndBeginRefreshing()
        startNetworkMonitor()
    }

    private func startNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let isSatisfied = path.status == .satisfied
                let wasDisconnected = self?.hasNetwork == false
                self?.hasNetwork = isSatisfied

                if isSatisfied && wasDisconnected {
                    self?.beginRefreshing()
                }
            }
        }
        networkMonitor.start(queue: .main)
    }

    func logIn(username: String, password: String, accountLocation: AccountLocation) {
        self.username = username
        self.password = password
        self.location = accountLocation.rawValue

        setUpClientAndBeginRefreshing()
    }

    private func setUpClientAndBeginRefreshing() {
        if let username, let password, let location, let accountLocation = AccountLocation(rawValue: location) {
            reading = .initial

            client = DexcomClient(
                username: username,
                password: password,
                accountLocation: accountLocation
            )

            beginRefreshing()
        }
    }

    func beginRefreshing() {
        guard let client else { return }

        Task<Void, Never> {
            if shouldRefreshReading {
                print("Refreshing reading")

                do {
                    let allReadings = try await client.getGlucoseReadings(
                        duration: .init(value: 3, unit: .hours)
                    ).sorted { $0.date < $1.date }

                    readings = allReadings.toLiveActivityReadings()

                    if let current = allReadings.last, current.date.timeIntervalSinceNow > -60 * 10 {
                        reading = .loaded(current)
                    } else {
                        reading = .noRecentReading
                    }
                } catch {
                    reading = .error(error)
                }
            }

            updateMessage()

            let refreshTime: TimeInterval? = {
                switch reading {
                case .initial:
                    return nil
                case .loaded(let reading):
                    // 5:05 after the last reading.
                    let fiveMinuteRefresh = 60 * 5 + reading.date.timeIntervalSinceNow + 5
                    // Refresh 5:05 after reading, then every 10s.
                    return max(10, fiveMinuteRefresh)
                case .noRecentReading:
                    return 10
                case .error(let error):
                    if error is DexcomError {
                        return nil
                    } else {
                        return 10
                    }
                }
            }()

            if let refreshTime {
                // Refresh at least every 60s for the time stamp.
                let refreshTime = min(60, refreshTime)

                print("Scheduling refresh in \(refreshTime / 60) minutes")
                
                let timer = Timer.scheduledTimer(withTimeInterval: refreshTime, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async { [weak self] in
                        self?.beginRefreshing()
                    }
                }

                timer.tolerance = 5
            }
        }
    }

    private func updateMessage() {
        switch reading {
        case .initial:
            message = "Loading..."
        case .loaded(let reading):
            if reading.date.timeIntervalSinceNow > -60 {
                message = "Just now"
            } else {
                message = reading.date.formatted(.relative(presentation: .numeric))
            }
        case .noRecentReading:
            message = "No recent glucose readings"
        case .error(let error):
            if error is DexcomError {
                message = "Try refreshing in 10 minutes"
            } else {
                message = "Unknown error"
            }
        }
    }
}
