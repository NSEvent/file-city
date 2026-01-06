//
//  File_CityApp.swift
//  File City
//
//  Created by Kevin on 1/5/26.
//

import SwiftUI

struct File_CityApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
