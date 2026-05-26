//
//  ViewModel.swift
//  LukaMini
//
//  Created by Kyle Bashour on 4/11/24.
//

import Dexcom
import Foundation
import Network
import SwiftUI

@MainActor
@Observable
final class AppModel {
    private let store: ProfileStore
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "com.kylebashour.LukaMini.network")

    private(set) var profileModels: [GlucoseProfileModel] = []
    private(set) var hasNetwork = false
    @ObservationIgnored var profileModelsDidChange: (() -> Void)?

    init(store: ProfileStore = ProfileStore()) {
        self.store = store
        syncProfileModels()
        startNetworkMonitor()
    }

    var hasProfiles: Bool { !profileModels.isEmpty }

    func model(for id: GlucoseProfile.ID) -> GlucoseProfileModel? {
        profileModels.first { $0.id == id }
    }

    func credentials(for id: GlucoseProfile.ID) -> ProfileCredentials? {
        store.credentials(for: id)
    }

    @discardableResult
    func addProfile(
        displayName: String,
        username: String,
        password: String,
        accountLocation: AccountLocation,
        showsInMenuBar: Bool
    ) -> GlucoseProfile.ID {
        let id = store.addProfile(
            displayName: displayName,
            username: username,
            password: password,
            accountLocation: accountLocation,
            showsInMenuBar: showsInMenuBar
        )
        syncProfileModels()
        model(for: id)?.beginRefreshing()
        return id
    }

    func updateProfile(
        id: GlucoseProfile.ID,
        displayName: String,
        username: String,
        password: String,
        accountLocation: AccountLocation,
        showsInMenuBar: Bool
    ) {
        store.updateProfile(
            id: id,
            displayName: displayName,
            username: username,
            password: password,
            accountLocation: accountLocation,
            showsInMenuBar: showsInMenuBar
        )
        syncProfileModels()
    }

    func setShowsInMenuBar(id: GlucoseProfile.ID, showsInMenuBar: Bool) {
        store.setShowsInMenuBar(id: id, showsInMenuBar: showsInMenuBar)
        syncProfileModels()
    }

    func removeProfile(id: GlucoseProfile.ID) {
        store.removeProfile(id: id)
        syncProfileModels()
    }

    func refreshAll() {
        for model in profileModels {
            model.beginRefreshing()
        }
    }

    private func syncProfileModels() {
        let existing = Dictionary(uniqueKeysWithValues: profileModels.map { ($0.id, $0) })

        profileModels = store.profiles.map { profile in
            let credentials = store.credentials(for: profile.id)
            if let model = existing[profile.id] {
                model.update(profile: profile, credentials: credentials)
                return model
            } else {
                return GlucoseProfileModel(profile: profile, credentials: credentials, hasNetwork: hasNetwork)
            }
        }

        profileModelsDidChange?()
    }

    private func startNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let isSatisfied = path.status == .satisfied
                let wasOffline = !self.hasNetwork
                self.hasNetwork = isSatisfied

                for model in self.profileModels {
                    model.setNetworkStatus(isSatisfied)
                }

                if isSatisfied && wasOffline {
                    self.refreshAll()
                }
            }
        }
        networkMonitor.start(queue: networkQueue)
    }
}

@MainActor
@Observable
final class GlucoseProfileModel: Identifiable {
    enum State {
        case initial
        case loaded(GlucoseReading)
        case noRecentReading
        case error(Error)
    }

    let id: GlucoseProfile.ID
    private(set) var profile: GlucoseProfile
    private(set) var reading: State = .initial
    private(set) var message: String?
    private(set) var readings: [LiveActivityState.Reading] = []

    @ObservationIgnored private var credentials: ProfileCredentials?
    @ObservationIgnored private var client: RemoteOrDirectClient?
    @ObservationIgnored private var hasNetwork: Bool
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var rateLimitRetryCount = 0
    @ObservationIgnored private var rateLimitedUntil: Date?

    init(profile: GlucoseProfile, credentials: ProfileCredentials?, hasNetwork: Bool) {
        self.id = profile.id
        self.profile = profile
        self.credentials = credentials
        self.hasNetwork = hasNetwork
        configureClient()
        updateMessage()
        beginRefreshing()
    }

    var isConfigured: Bool {
        credentials?.isComplete == true
    }

    var displayName: String {
        if !profile.displayName.isEmpty { return profile.displayName }
        if let username = credentials?.username, !username.isEmpty { return username }
        return "User"
    }

    func update(profile: GlucoseProfile, credentials: ProfileCredentials?) {
        let credentialsChanged = credentials != self.credentials
        let locationChanged = profile.accountLocation != self.profile.accountLocation

        self.profile = profile
        self.credentials = credentials

        if credentialsChanged || locationChanged {
            configureClient()
            reading = .initial
            readings = []
        }

        updateMessage()
        beginRefreshing()
    }

    func setNetworkStatus(_ hasNetwork: Bool) {
        self.hasNetwork = hasNetwork
        updateMessage()
    }

    func beginRefreshing() {
        refreshTask?.cancel()

        guard profile.showsInMenuBar, isConfigured, hasNetwork, let client else {
            refreshTask = nil
            return
        }

        refreshTask = Task { [weak self] in
            await self?.refreshLoop(client: client)
        }
    }

    private func configureClient() {
        if let credentials, credentials.isComplete {
            client = RemoteOrDirectClient(
                username: credentials.username,
                password: credentials.password,
                accountLocation: profile.accountLocation
            )
        } else {
            client = nil
        }
    }

    private func refreshLoop(client: RemoteOrDirectClient) async {
        while !Task.isCancelled {
            await fetchReadings(client: client)
            updateMessage()

            guard let delay = nextRefreshDelay() else { return }
            do {
                try await Task.sleep(for: .seconds(min(60, delay)))
            } catch {
                return
            }
        }
    }

    private func fetchReadings(client: RemoteOrDirectClient) async {
        guard shouldRefreshReading else { return }

        do {
            let allReadings = try await client.getGlucoseReadings(
                duration: .init(value: 24, unit: .hours)
            ).sorted { $0.date < $1.date }

            guard !Task.isCancelled else { return }
            readings = allReadings.toLiveActivityReadings()
            rateLimitRetryCount = 0
            rateLimitedUntil = nil

            if let current = allReadings.last, current.date.timeIntervalSinceNow > -60 * 10 {
                reading = .loaded(current)
            } else {
                reading = .noRecentReading
            }
        } catch {
            guard !Task.isCancelled else { return }
            if (error as? DexcomDecodingError)?.statusCode == 429 {
                rateLimitRetryCount += 1
                rateLimitedUntil = .now.addingTimeInterval(
                    Self.rateLimitBackoff(retryCount: rateLimitRetryCount)
                )
            } else {
                rateLimitRetryCount = 0
                rateLimitedUntil = nil
            }
            reading = .error(error)
        }
    }

    private var shouldRefreshReading: Bool {
        if let rateLimitedUntil, rateLimitedUntil > .now {
            return false
        }
        switch reading {
        case .initial, .error, .noRecentReading:
            return true
        case .loaded(let reading):
            return reading.date.timeIntervalSinceNow < -60 * 5
        }
    }

    private func nextRefreshDelay() -> TimeInterval? {
        switch reading {
        case .initial:
            return nil
        case .loaded(let reading):
            // 5:05 after the last reading, then every 10s.
            return max(10, 60 * 5 + reading.date.timeIntervalSinceNow + 5)
        case .noRecentReading:
            return 10
        case .error(let error):
            if let rateLimitedUntil {
                return max(1, rateLimitedUntil.timeIntervalSinceNow)
            }
            return error is DexcomError ? nil : 10
        }
    }

    /// Exponential backoff for HTTP 429 from Dexcom. Rate limits are per-account
    /// and the window often outlasts a short wait, so escalate aggressively.
    /// 120s → 240s → 480s → 600s (capped), with ±30s jitter.
    private static func rateLimitBackoff(retryCount: Int) -> TimeInterval {
        let base: TimeInterval = 120
        let cap: TimeInterval = 600
        let scaled = base * pow(2, Double(min(retryCount, 4)))
        return min(scaled, cap) + TimeInterval.random(in: -30...30)
    }

    private func updateMessage() {
        guard isConfigured else {
            message = "Not signed in"
            return
        }

        switch reading {
        case .initial:
            message = hasNetwork ? "Loading..." : "Offline"
        case .loaded(let reading):
            if reading.date.timeIntervalSinceNow > -60 {
                message = "Just now"
            } else {
                message = reading.date.formatted(.relative(presentation: .numeric))
            }
        case .noRecentReading:
            message = "No recent glucose readings"
        case .error(let error):
            if (error as? DexcomDecodingError)?.statusCode == 429 {
                message = "Rate limited, retrying soon"
            } else if error is DexcomError {
                message = "Try refreshing in 10 minutes"
            } else {
                message = "Unknown error"
            }
        }
    }
}
