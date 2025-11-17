//
//  ContentView.swift
//  LukaMini
//
//  Created by Kyle Bashour on 4/11/24.
//

import Dexcom
import SwiftUI
import KeychainAccess

struct SettingsView: View {
    @AppStorage(.useMMOLKey) private var mmol = false

    @State private var username = Keychain.standard[.usernameKey] ?? ""
    @State private var password = Keychain.standard[.passwordKey] ?? ""
    @State private var accountLocation = UserDefaults.standard
        .string(forKey: .locationKey)
        .flatMap { AccountLocation(rawValue: $0) } ?? .usa

    @Environment(\.dismissWindow) private var dismissWindow

    var didLogIn: (String, String, AccountLocation) -> Void

    private let locations: [AccountLocation] = [
        .usa,
        .worldwide,
        .apac,
    ]

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Units")
                Spacer()
                Picker("Units", selection: $mmol) {
                    Text("mg/dl").tag(false)
                    Text("mmol/L").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack {
                Text("Account location")
                Spacer()
                Picker("Account location", selection: $accountLocation) {
                    ForEach(locations) {
                        Text($0.displayName).tag($0)
                    }
                }
                .labelsHidden()
            }

            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            Button("Sign In") {
                Keychain.standard[.usernameKey] = username
                Keychain.standard[.passwordKey] = password
                UserDefaults.standard.set(accountLocation.rawValue, forKey: .locationKey)

                didLogIn(username, password, accountLocation)

                dismissWindow(id: .settingsWindow)
            }
            .disabled(username.isEmpty || password.isEmpty)
            .frame(maxWidth: .infinity, alignment: .trailing)

            Text("Sign in using your Dexcom username and password. **Dexcom share must be enabled with at least one follower**, but sign in using **your own Dexcom credentials**, not the followers. If your username is a phone number, format it with a + and the area code, for example +12223334444.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
                .padding(.vertical)
                .font(.footnote)
        }
        .padding()
        .frame(width: 300)
    }
}

extension AccountLocation: Identifiable {
    public var id: Self { self }

    var displayName: String {
        switch self {
        case .usa:
            "United States"
        case .apac:
            "Japan"
        case .worldwide:
            "Anywhere Else"
        }
    }
}

#Preview {
    SettingsView(didLogIn: {_, _, _ in})
}
