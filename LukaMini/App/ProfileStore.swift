//
//  ProfileStore.swift
//  LukaMini
//

import Dexcom
import Foundation
import KeychainAccess

struct GlucoseProfile: Codable, Hashable, Identifiable {
    var id = UUID()
    var displayName: String
    var accountLocation: AccountLocation
    var showsInMenuBar: Bool = true
}

struct ProfileCredentials: Equatable {
    var username: String
    var password: String

    var isComplete: Bool {
        !username.isEmpty && !password.isEmpty
    }
}

final class ProfileStore {
    private let defaults: UserDefaults
    private let keychain: Keychain
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private(set) var profiles: [GlucoseProfile] = []

    init(defaults: UserDefaults = .standard, keychain: Keychain = .standard) {
        self.defaults = defaults
        self.keychain = keychain

        if let data = defaults.data(forKey: .profilesKey) {
            profiles = (try? decoder.decode([GlucoseProfile].self, from: data)) ?? []
        } else if let migrated = Self.migrateLegacyProfile(defaults: defaults, keychain: keychain) {
            profiles = [migrated]
            save()
        }
    }

    func credentials(for id: GlucoseProfile.ID) -> ProfileCredentials? {
        guard let username = keychain[Self.usernameKey(for: id)],
              let password = keychain[Self.passwordKey(for: id)] else {
            return nil
        }
        return ProfileCredentials(username: username, password: password)
    }

    @discardableResult
    func addProfile(
        displayName: String,
        username: String,
        password: String,
        accountLocation: AccountLocation,
        showsInMenuBar: Bool
    ) -> GlucoseProfile.ID {
        let profile = GlucoseProfile(
            displayName: displayName.trimmed,
            accountLocation: accountLocation,
            showsInMenuBar: showsInMenuBar
        )
        profiles.append(profile)
        writeCredentials(username: username, password: password, for: profile.id)
        save()
        return profile.id
    }

    func updateProfile(
        id: GlucoseProfile.ID,
        displayName: String,
        username: String,
        password: String,
        accountLocation: AccountLocation,
        showsInMenuBar: Bool
    ) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].displayName = displayName.trimmed
        profiles[index].accountLocation = accountLocation
        profiles[index].showsInMenuBar = showsInMenuBar
        writeCredentials(username: username, password: password, for: id)
        save()
    }

    func setShowsInMenuBar(id: GlucoseProfile.ID, showsInMenuBar: Bool) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].showsInMenuBar = showsInMenuBar
        save()
    }

    func removeProfile(id: GlucoseProfile.ID) {
        profiles.removeAll { $0.id == id }
        keychain[Self.usernameKey(for: id)] = nil
        keychain[Self.passwordKey(for: id)] = nil
        save()
    }

    private func writeCredentials(username: String, password: String, for id: GlucoseProfile.ID) {
        keychain[Self.usernameKey(for: id)] = username.trimmed
        keychain[Self.passwordKey(for: id)] = password
    }

    private func save() {
        guard let data = try? encoder.encode(profiles) else { return }
        defaults.set(data, forKey: .profilesKey)
    }

    private static func migrateLegacyProfile(defaults: UserDefaults, keychain: Keychain) -> GlucoseProfile? {
        guard let username = keychain[.usernameKey], !username.isEmpty,
              let password = keychain[.passwordKey], !password.isEmpty else {
            return nil
        }

        let accountLocation = defaults.string(forKey: .locationKey)
            .flatMap(AccountLocation.init(rawValue:)) ?? .usa

        let profile = GlucoseProfile(displayName: "", accountLocation: accountLocation)
        keychain[usernameKey(for: profile.id)] = username
        keychain[passwordKey(for: profile.id)] = password
        return profile
    }

    private static func usernameKey(for id: GlucoseProfile.ID) -> String {
        "profile.\(id.uuidString).username"
    }

    private static func passwordKey(for id: GlucoseProfile.ID) -> String {
        "profile.\(id.uuidString).password"
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
