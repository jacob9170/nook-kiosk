//
//  ContentView.swift
//  Nook
//

import SwiftUI

struct RootView: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    @State private var showAccessibility = false
    @State private var lastInteraction = Date.now
    @State private var idleWarning = false

    /// Seconds of no touches before the kiosk resets. Staff get longer.
    /// "Still there?" shows for the last 15 seconds.
    private var resetAfter: TimeInterval { store.isAdmin ? 180 : 60 }
    private var idleAfter: TimeInterval { resetAfter - 15 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.ignoresSafeArea()
                if store.screen == .home { AmbientBackground() }

                VStack(spacing: 0) {
                    TopBar(showAccessibility: $showAccessibility)
                    screen
                        .id(store.screen.key)
                        .transition(settings.reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, geo.size.width > 900 ? 48 : 24)
                .padding(.bottom, 24)
                // Low reach: drop the whole interface into the bottom of the screen.
                .padding(.top, settings.lowReach ? geo.size.height * 0.3 : 0)
                .animation(settings.animation, value: store.screen)
                .animation(settings.animation, value: settings.lowReach)
                .animation(settings.animation, value: store.loginPrompt?.id)
                .animation(settings.animation, value: store.toast)

                if let prompt = store.loginPrompt {
                    LoginView(prompt: prompt)
                        .id(prompt.id)
                        .transition(.opacity)
                }

                if let toast = store.toast {
                    VStack {
                        Spacer()
                        Text(toast)
                            .kFont(19, .semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 18)
                            .background(settings.ink, in: .capsule)
                            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                            .padding(.bottom, 40)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
                }

                if idleWarning {
                    IdleOverlay(deadline: lastInteraction.addingTimeInterval(resetAfter)) {
                        poke()
                    }
                    .transition(.opacity)
                }
            }
        }
        .foregroundStyle(settings.ink)
        .simultaneousGesture(SpatialTapGesture().onEnded { _ in poke() })
        .sheet(isPresented: $showAccessibility) {
            AccessibilityPanel()
                .environment(settings)
                .presentationDetents([.large])
                .simultaneousGesture(SpatialTapGesture().onEnded { _ in poke() })
        }
        .onChange(of: store.screen) { poke() }
        .onChange(of: store.profile) { _, profile in
            // Signing out (or timing out) closes screens that belong to a profile.
            if profile == nil && store.screen.requiresSignIn { store.goHome() }
        }
        .task {
            await store.refresh()
            #if DEBUG
            openDebugScreen()
            #endif
        }
        .task { await watchForIdle() }
    }

    @ViewBuilder
    private var screen: some View {
        switch store.screen {
        case .home: HomeView()
        case .scan(let mode): ScanView(mode: mode)
        case .confirm(let booking, let mode): ConfirmView(booking: booking, mode: mode)
        case .locker(let booking, let mode, let condition): LockerOpenView(booking: booking, mode: mode, condition: condition)
        case .done(let booking, let mode): DoneView(booking: booking, mode: mode)
        case .available: AvailableView()
        case .schedule: ScheduleView()
        case .help: HelpView()
        case .requests: RequestsView()
        case .newRequest: NewRequestView()
        case .admin: AdminView()
        }
    }

    #if DEBUG
    /// `-startScreen schedule` etc. as a launch argument jumps straight to a screen.
    private func openDebugScreen() {
        switch UserDefaults.standard.string(forKey: "startScreen") {
        case "available": store.go(.available)
        case "schedule": store.go(.schedule)
        case "help": store.go(.help)
        case "requests": store.go(.requests)
        case "scan": store.go(.scan(.borrow))
        case "login": store.requireLogin("Sign in to post a request from your apartment.") { _ in }
        case "admin":
            Task {
                _ = try? await store.signIn(unit: "0000", pin: "2468")
                store.go(.admin)
            }
        default: break
        }
    }
    #endif

    private func poke() {
        lastInteraction = .now
        if idleWarning { withAnimation(settings.animation) { idleWarning = false } }
    }

    private func watchForIdle() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            let idle = Date.now.timeIntervalSince(lastInteraction)
            // Never time out while a locker door is open.
            if case .locker = store.screen { continue }
            let atRest = store.screen == .home && !settings.isCustomised && !showAccessibility
                && store.profile == nil && store.loginPrompt == nil

            if idle >= resetAfter {
                idleWarning = false
                showAccessibility = false
                settings.reset()
                store.endSession()
                if store.screen != .home { store.goHome() }
                lastInteraction = .now
            } else if idle >= idleAfter && !atRest && !idleWarning {
                withAnimation(settings.animation) { idleWarning = true }
                settings.speak("Are you still there? Tap the screen to keep going.")
            }
        }
    }
}

extension KioskScreen {
    var key: String {
        switch self {
        case .home: "home"
        case .scan(let m): "scan-\(m)"
        case .confirm(let b, let m): "confirm-\(b.code)-\(m)"
        case .locker(let b, let m, _): "locker-\(b.code)-\(m)"
        case .done(let b, let m): "done-\(b.code)-\(m)"
        case .available: "available"
        case .schedule: "schedule"
        case .help: "help"
        case .requests: "requests"
        case .newRequest: "new-request"
        case .admin: "admin"
        }
    }

    var requiresSignIn: Bool {
        switch self {
        case .schedule, .requests, .newRequest, .admin: true
        default: false
        }
    }

    var showsHelpButton: Bool {
        switch self {
        case .help, .locker, .admin: false
        default: true
        }
    }

    var title: String? {
        switch self {
        case .home: nil
        case .scan(let m): m == .borrow ? "Borrow an item" : "Return an item"
        case .confirm(_, let m): m == .borrow ? "Check your booking" : "Check your return"
        case .locker: nil
        case .done: nil
        case .available: "What's in the lockers"
        case .schedule: "Locker schedule"
        case .help: "Help"
        case .requests: "Community requests"
        case .newRequest: "New request"
        case .admin: "Building admin"
        }
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    @Binding var showAccessibility: Bool

    var body: some View {
        HStack(spacing: 20) {
            if store.screen == .home {
                Wordmark(building: store.buildingName)
            } else if case .locker = store.screen {
                Wordmark(building: store.buildingName)
            } else {
                if store.screen == .admin {
                    Button {
                        // Leaving admin always signs staff out.
                        store.endSession()
                        store.goHome()
                        store.showToast("Signed out of admin")
                    } label: {
                        Label("Exit admin", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button {
                        store.goHome()
                    } label: {
                        Label("Home", systemImage: "chevron.left")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }

            if let title = store.screen.title {
                Text(title)
                    .kFont(22, .semibold)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            } else {
                Spacer()
            }

            if store.screen == .home {
                Clock()
            }

            AccountButton()

            if store.screen.showsHelpButton {
                Button {
                    store.go(.help)
                } label: {
                    Image(systemName: "questionmark")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(settings.ink)
                        .frame(width: 68, height: 68)
                        .background(settings.surface, in: .circle)
                        .overlay(Circle().strokeBorder(settings.highContrast ? settings.ink : .clear, lineWidth: 2))
                }
                .buttonStyle(TileButtonStyle())
                .accessibilityLabel("Help")
            }

            Button {
                showAccessibility = true
            } label: {
                Image(systemName: "accessibility")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(settings.isCustomised ? .white : settings.accent)
                    .frame(width: 68, height: 68)
                    .background(settings.isCustomised ? settings.accent : settings.accentSoft, in: .circle)
                    .overlay(Circle().strokeBorder(settings.highContrast ? settings.ink : .clear, lineWidth: 2))
            }
            .buttonStyle(TileButtonStyle())
            .accessibilityLabel("Accessibility options")
        }
        .frame(height: 96)
    }
}

/// Optional sign in. Shows who's signed in, with a menu to sign out.
private struct AccountButton: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings

    var body: some View {
        if let profile = store.profile {
            Menu {
                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") {
                    store.endSession()
                    store.showToast("Signed out")
                }
            } label: {
                HStack(spacing: 10) {
                    Text(String(profile.firstName.prefix(1)))
                        .kFont(18, .bold, design: .rounded)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(settings.accent, in: .circle)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(profile.firstName).kFont(17, .semibold)
                        Text(profile.isAdmin ? "Building staff" : "Apt \(profile.unit)").kFont(13).foregroundStyle(settings.secondary)
                    }
                }
                .foregroundStyle(settings.ink)
                .padding(.leading, 12)
                .padding(.trailing, 20)
                .frame(height: 68)
                .background(settings.accentSoft, in: .capsule)
            }
            .accessibilityLabel("Signed in as \(profile.firstName), apartment \(profile.unit). Sign out")
        } else {
            Button {
                store.requireLogin("Sign in to book items and post requests from your apartment.") { _ in }
            } label: {
                Label("Sign in", systemImage: "person.crop.circle")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}

private struct Wordmark: View {
    @Environment(KioskSettings.self) private var settings
    let building: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [settings.accent, Color(hex: 0x8B5CF6)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 2) {
                Text("nook")
                    .kFont(24, .bold, design: .rounded)
                    .tracking(-0.5)
                Text("\(building) · Community Hub")
                    .kFont(14, .medium)
                    .foregroundStyle(settings.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct Clock: View {
    @Environment(KioskSettings.self) private var settings

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .trailing, spacing: 2) {
                Text(context.date, format: .dateTime.hour().minute())
                    .kFont(24, .semibold, design: .rounded)
                    .monospacedDigit()
                Text(context.date, format: .dateTime.weekday(.wide).day().month())
                    .kFont(14, .medium)
                    .foregroundStyle(settings.secondary)
            }
        }
    }
}

// MARK: - Idle

private struct IdleOverlay: View {
    @Environment(KioskSettings.self) private var settings
    let deadline: Date
    let onStay: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 24) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(max(0, Int(deadline.timeIntervalSince(context.date).rounded())))")
                        .kFont(72, .bold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(settings.accent)
                        .contentTransition(.numericText(countsDown: true))
                }
                Text("Still there?")
                    .kFont(34, .bold)
                Text("We'll head back to the start soon to keep things private.")
                    .kFont(20)
                    .foregroundStyle(settings.secondary)
                    .multilineTextAlignment(.center)
                Button("I'm still here", action: onStay)
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: 360)
            }
            .card(padding: 48)
            .frame(maxWidth: 560)
        }
    }
}

#Preview {
    RootView()
        .environment(KioskStore())
        .environment(KioskSettings())
}
