//
//  AppDelegate.swift
//  LukaMini
//
//  Created by Kyle Bashour on 4/12/24.
//

import AppKit
import SwiftUI
import Dexcom
import KeychainAccess

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = ViewModel()
    let loginHelper = LoginItemHelper()

    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        if !model.isLoggedIn {
            showSettings()
        }

        observeModel()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    // MARK: - Observation

    private func observeModel() {
        withObservationTracking {
            updateStatusBarButton()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeModel()
            }
        }
    }

    @objc private func defaultsDidChange() {
        updateStatusBarButton()
    }

    private func updateStatusBarButton() {
        guard let button = statusItem.button else { return }

        let useMMOL = UserDefaults.standard.bool(forKey: .useMMOLKey)

        if model.isLoggedIn {
            switch model.reading {
            case .initial:
                button.image = nil
                button.title = "--"
            case .loaded(let reading):
                let value = reading.value.formatted(.glucose(useMMOL ? .mmolL : .mgdl))
                button.image = reading.trend.nsImage
                button.title = value
            case .noRecentReading, .error:
                button.image = NSImage(systemSymbolName: "icloud.slash", accessibilityDescription: "Error")
                button.title = ""
            }
        } else {
            button.image = nil
            button.title = "Luka"
        }
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let graphItem = NSMenuItem()
        let hostingView = NSHostingView(rootView: MenuGraphView(model: model))
        hostingView.frame.size = hostingView.fittingSize
        graphItem.view = hostingView
        menu.addItem(graphItem)
        menu.addItem(.separator())

        if let message = model.message {
            let messageItem = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            messageItem.isEnabled = false
            menu.addItem(messageItem)
            menu.addItem(.separator())
        }

        if model.isLoggedIn {
            let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "")
            refreshItem.target = self
            refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
            menu.addItem(refreshItem)
        }

        menu.addItem(.separator())

        let loginToggle = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginToggle.target = self
        loginToggle.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        loginToggle.state = loginHelper.isEnabled ? .on : .off
        menu.addItem(loginToggle)

        let settingsTitle = model.isLoggedIn ? "Settings" : "Log In"
        let settingsImageName = model.isLoggedIn ? "gear" : "person"
        let settingsItem = NSMenuItem(title: settingsTitle, action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: settingsImageName, accessibilityDescription: nil)
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "xmark.rectangle", accessibilityDescription: nil)
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func didWake() {
        model.beginRefreshing()
    }

    @objc private func refresh() {
        model.beginRefreshing()
    }

    @objc private func toggleLaunchAtLogin() {
        loginHelper.isEnabled.toggle()
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(didLogIn: model.logIn) { [weak self] in
                self?.settingsWindow?.close()
            }
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.title = "Luka Mini"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }

        settingsWindow?.level = .floating
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

struct MenuGraphView: View {
    var model: ViewModel

    var body: some View {
        LineChart(
            range: .threeHours,
            style: .dots,
            readings: model.readings,
            lineWidth: 1.5,
            showAxisLabels: true,
            useFullYRange: true
        )
        .frame(width: 280, height: 130)
        .padding([.horizontal, .top])
    }
}

extension TrendDirection {
    var nsImage: NSImage? {
        let image: NSImage? = switch self {
        case .none:
            nil
        case .doubleUp:
            NSImage(named: "arrow.up.double")
        case .singleUp:
            NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil)
        case .fortyFiveUp:
            NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil)
        case .flat:
            NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)
        case .fortyFiveDown:
            NSImage(systemSymbolName: "arrow.down.right", accessibilityDescription: nil)
        case .singleDown:
            NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil)
        case .doubleDown:
            NSImage(named: "arrow.down.double")
        case .notComputable:
            NSImage(systemSymbolName: "questionmark", accessibilityDescription: nil)
        case .rateOutOfRange:
            NSImage(systemSymbolName: "exclamationmark", accessibilityDescription: nil)
        }

        image?.isTemplate = true
        return image
    }
}
