//
//  LukaMiniApp.swift
//  LukaMini
//
//  Created by Kyle Bashour on 4/11/24.
//

import SwiftUI

@main
struct LukaMiniApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
