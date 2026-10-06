//
//  NookApp.swift
//  Nook
//

import SwiftUI
import UIKit

@main
struct NookApp: App {
    @State private var store = KioskStore()
    @State private var settings = KioskSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(settings)
                .preferredColorScheme(.light)
                .persistentSystemOverlays(.hidden)
                .statusBarHidden()
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}
