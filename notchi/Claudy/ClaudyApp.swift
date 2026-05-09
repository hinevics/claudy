//
//  ClaudyApp.swift
//  Claudy
//
//  Created by Ruban on 2026-01-30.
//

import SwiftUI

@main
struct ClaudyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
