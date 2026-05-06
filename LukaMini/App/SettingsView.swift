//
//  SettingsView.swift
//  LukaMini
//
//  Created by Kyle Bashour on 4/11/24.
//

import AppKit
import Dexcom
import SwiftUI

struct SettingsView: View {
    var appModel: AppModel
    @Bindable var loginHelper: LoginItemHelper

    @AppStorage(.useMMOLKey) private var useMMOL = false
    @AppStorage(.graphRangeKey) private var graphRange: GraphRange = .threeHours
    @AppStorage(.showNamesForMultipleUsersKey) private var showNamesForMultipleUsers = true

    @State private var selection: SettingsSelection = .general
    @State private var editor = ProfileEditorState()
    @State private var original = ProfileEditorState()
    @State private var isShowingDeleteAlert = false

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
                .help("Toggle Sidebar")
            }
        }
        .onAppear { selectInitial() }
        .onChange(of: selection) { _, new in loadEditor(for: new) }
        .onChange(of: appModel.profileModels.map(\.id)) { _, ids in reconcileSelection(with: ids) }
        .alert("Delete User?", isPresented: $isShowingDeleteAlert) {
            Button("Delete", role: .destructive, action: deleteSelectedProfile)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes \(deleteAlertProfileName) from Luka Mini and deletes the saved Dexcom credentials for this user.")
        }
        .frame(minWidth: 650, idealWidth: 650, minHeight: 450, idealHeight: 450)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Text("General").tag(SettingsSelection.general)

                Section("Users") {
                    if appModel.profileModels.isEmpty && selection != .newProfile {
                        Text("No Users").foregroundStyle(.secondary)
                    }

                    ForEach(appModel.profileModels) { model in
                        ProfileListRow(model: model, useMMOL: useMMOL)
                            .tag(SettingsSelection.profile(model.id))
                    }

                    if selection == .newProfile {
                        Text("New User")
                            .fontWeight(.medium)
                            .padding(.vertical, 4)
                            .tag(SettingsSelection.newProfile)
                    }
                }
            }
            .listStyle(.sidebar)

            HStack(spacing: 0) {
                SidebarAddRemoveControl(canRemove: selection.isProfile) {
                    selection = .newProfile
                } remove: {
                    if selection == .newProfile {
                        selection = appModel.profileModels.first.map { .profile($0.id) } ?? .general
                    } else {
                        isShowingDeleteAlert = true
                    }
                }
                .frame(width: 68, height: 24, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(8)
            .background(.bar)
        }
        .background(.bar)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general:
            generalDetail
        case .newProfile, .profile:
            profileDetail.id(selection)
        }
    }

    private var generalDetail: some View {
        Form {
            Section("Menu Bar") {
                Toggle("Show names when multiple users are visible", isOn: $showNamesForMultipleUsers)

                Picker("Graph range", selection: $graphRange) {
                    ForEach(GraphRange.allCases) { Text($0.abbreviatedName).tag($0) }
                }

                Picker("Units", selection: $useMMOL) {
                    Text("mg/dL").tag(false)
                    Text("mmol/L").tag(true)
                }
                .pickerStyle(.segmented)
            }

            Section("App") {
                Toggle("Launch at login", isOn: $loginHelper.isEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private var profileDetail: some View {
        Form {
            Section("User") {
                TextField("Name", text: $editor.displayName, prompt: Text(editor.namePlaceholder))
                    .textFieldStyle(.roundedBorder)

                Toggle("Show in menu bar", isOn: showsInMenuBarBinding)
            }

            Section("Dexcom") {
                Picker("Account location", selection: $editor.accountLocation) {
                    ForEach(AccountLocation.allCases) { Text($0.displayName).tag($0) }
                }

                TextField("Username", text: $editor.username)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $editor.password)
                    .textFieldStyle(.roundedBorder)

                Text("Sign in using this user’s Dexcom username and password. Dexcom Share must be enabled with at least one follower, but use this user’s own Dexcom credentials, not the follower’s. If the username is a phone number, format it with a + and country code, for example +12223334444.")
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar
        }
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer()
                Button(selection == .newProfile ? "Add User" : "Save Changes") {
                    saveProfile()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding()
        }
        .background(.bar)
    }

    // MARK: - Derived

    private var canSave: Bool {
        editor.canSave && editor != original
    }

    private var deleteAlertProfileName: String {
        editor.resolvedDisplayName.isEmpty ? "this user" : editor.resolvedDisplayName
    }

    /// Toggling menu-bar visibility on an existing profile auto-saves so the
    /// menu bar updates immediately without requiring the user to hit Save.
    private var showsInMenuBarBinding: Binding<Bool> {
        Binding {
            editor.showsInMenuBar
        } set: { value in
            editor.showsInMenuBar = value
            original.showsInMenuBar = value
            if let id = editor.id {
                appModel.setShowsInMenuBar(id: id, showsInMenuBar: value)
            }
        }
    }

    // MARK: - Actions

    private func selectInitial() {
        selection = appModel.profileModels.isEmpty ? .newProfile : .general
        loadEditor(for: selection)
    }

    private func loadEditor(for selection: SettingsSelection) {
        switch selection {
        case .general:
            break
        case .newProfile:
            editor = ProfileEditorState()
            original = editor
        case .profile(let id):
            if let model = appModel.model(for: id) {
                editor = ProfileEditorState(profile: model.profile, credentials: appModel.credentials(for: id))
                original = editor
            }
        }
    }

    private func reconcileSelection(with profileIDs: [GlucoseProfile.ID]) {
        guard case .profile(let id) = selection else { return }
        if profileIDs.contains(id) {
            loadEditor(for: selection)
        } else if let firstID = profileIDs.first {
            selection = .profile(firstID)
        } else {
            selection = .general
        }
    }

    private func saveProfile() {
        if let id = editor.id {
            appModel.updateProfile(
                id: id,
                displayName: editor.displayName,
                username: editor.username,
                password: editor.password,
                accountLocation: editor.accountLocation,
                showsInMenuBar: editor.showsInMenuBar
            )
            loadEditor(for: selection)
        } else {
            let id = appModel.addProfile(
                displayName: editor.displayName,
                username: editor.username,
                password: editor.password,
                accountLocation: editor.accountLocation,
                showsInMenuBar: editor.showsInMenuBar
            )
            selection = .profile(id)
        }
    }

    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(
            #selector(NSSplitViewController.toggleSidebar(_:)),
            with: nil
        )
    }

    private func deleteSelectedProfile() {
        guard case .profile(let id) = selection else { return }
        appModel.removeProfile(id: id)
        selection = appModel.profileModels.first.map { .profile($0.id) } ?? .general
    }
}

// MARK: - Selection

private enum SettingsSelection: Hashable {
    case general
    case newProfile
    case profile(GlucoseProfile.ID)

    var isProfile: Bool {
        switch self {
        case .profile, .newProfile: true
        case .general: false
        }
    }
}

// MARK: - Editor State

private struct ProfileEditorState: Equatable {
    var id: GlucoseProfile.ID?
    var displayName: String = ""
    var username: String = ""
    var password: String = ""
    var accountLocation: AccountLocation = .usa
    var showsInMenuBar: Bool = true

    var canSave: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    var resolvedDisplayName: String {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { return trimmedName }
        return username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var namePlaceholder: String {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Optional" : trimmed
    }

    init() {}

    init(profile: GlucoseProfile, credentials: ProfileCredentials?) {
        self.id = profile.id
        self.displayName = profile.displayName
        self.username = credentials?.username ?? ""
        self.password = credentials?.password ?? ""
        self.accountLocation = profile.accountLocation
        self.showsInMenuBar = profile.showsInMenuBar
    }
}

// MARK: - Rows

private struct ProfileListRow: View {
    var model: GlucoseProfileModel
    var useMMOL: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(model.profile.showsInMenuBar ? model.message ?? "Not signed in" : "Hidden")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if model.profile.showsInMenuBar, case .loaded(let reading) = model.reading {
                Text(reading.value.formatted(.glucose(useMMOL ? .mmolL : .mgdl)))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 52, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sidebar segmented control

private struct SidebarAddRemoveControl: NSViewRepresentable {
    var canRemove: Bool
    var add: () -> Void
    var remove: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(add: add, remove: remove)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentCount = 2
        control.trackingMode = .momentary
        control.segmentStyle = .smallSquare
        control.controlSize = .small
        control.target = context.coordinator
        control.action = #selector(Coordinator.performAction(_:))

        control.setImage(NSImage(systemSymbolName: "plus", accessibilityDescription: "Add User"), forSegment: 0)
        control.setImage(NSImage(systemSymbolName: "minus", accessibilityDescription: "Delete User"), forSegment: 1)
        control.setToolTip("Add User", forSegment: 0)
        control.setToolTip("Delete User", forSegment: 1)
        control.setWidth(32, forSegment: 0)
        control.setWidth(32, forSegment: 1)

        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.add = add
        context.coordinator.remove = remove
        control.setEnabled(canRemove, forSegment: 1)
    }

    final class Coordinator: NSObject {
        var add: () -> Void
        var remove: () -> Void

        init(add: @escaping () -> Void, remove: @escaping () -> Void) {
            self.add = add
            self.remove = remove
        }

        @objc func performAction(_ sender: NSSegmentedControl) {
            switch sender.selectedSegment {
            case 0: add()
            case 1: remove()
            default: break
            }
            sender.selectedSegment = -1
        }
    }
}

extension AccountLocation: @retroactive Identifiable, @retroactive CaseIterable {
    public static var allCases: [AccountLocation] { [.usa, .worldwide, .apac] }
    public var id: Self { self }

    var displayName: String {
        switch self {
        case .usa: "United States"
        case .apac: "Japan"
        case .worldwide: "Anywhere Else"
        }
    }
}
