//
//  Keychain.swift
//  LukaMini
//
//  Created by Kyle Bashour on 4/12/24.
//

import Security
import KeychainAccess

extension Keychain {
    static var standard: Keychain {
        // Local login keychain (no iCloud sync). The synchronizable/data-protection
        // keychain requires a real Apple team + keychain entitlement, which an ad-hoc
        // (App Store-less) local build doesn't have, so saves would silently fail.
        Keychain()
    }
}
