//
//  HomeView.swift
//  Nook
//

import SwiftUI

struct HomeView: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height * 1.1
            let layout = wide ? AnyLayout(HStackLayout(alignment: .bottom, spacing: 40))
                              : AnyLayout(VStackLayout(alignment: .leading, spacing: 32))
            VStack(spacing: 24) {
                layout {
                    intro
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 20) {
                        ActionTile(mode: .borrow)
                        ActionTile(mode: .return)
                    }
                    .frame(maxWidth: wide ? geo.size.width * 0.52 : .infinity)
                    .frame(maxHeight: wide ? .infinity : 340)
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: 16) {
                    ShortcutTile(title: "What's available", subtitle: "\(store.availableCount) items ready now",
                                 symbol: "square.grid.2x2.fill") { store.go(.available) }
                    ShortcutTile(title: "Schedule", subtitle: "Pickups & returns",
                                 symbol: "calendar", locked: store.profile == nil) {
                        store.requireLogin("Sign in to see the locker schedule.") { _ in store.go(.schedule) }
                    }
                    ShortcutTile(title: "Requests", subtitle: "\(store.openRequests.count) up for grabs",
                                 symbol: "hand.raised.fill", locked: store.profile == nil) {
                        store.requireLogin("Sign in to see and help with community requests.") { _ in store.go(.requests) }
                    }
                }
            }
            .padding(.top, 8)
        }
        .onAppear {
            settings.speak("Welcome to the Nook community hub. Tap Borrow to collect an item, or Return to bring one back.")
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 20) {
            TimelineView(.everyMinute) { context in
                Text(greeting(for: context.date))
                    .kFont(20, .semibold)
                    .foregroundStyle(settings.accent)
            }
            Text("Borrow it.\nUse it.\nBring it back.")
                .kFont(64, .bold)
                .tracking(-2)
                .minimumScaleFactor(0.6)
            HStack(spacing: 12) {
                Image(systemName: "qrcode")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(settings.accent)
                Text("Have your booking QR code ready in the Nook app.")
                    .kFont(18, .medium)
                    .foregroundStyle(settings.secondary)
            }
        }
        .padding(.bottom, 8)
    }

    private func greeting(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }
}

private struct ActionTile: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    let mode: KioskMode

    private var filled: Bool { mode == .borrow }

    var body: some View {
        Button {
            store.go(.scan(mode))
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: mode == .borrow ? "arrow.up.forward" : "arrow.down.backward")
                    .font(.system(size: 34, weight: .bold))
                    .frame(width: 76, height: 76)
                    .background(filled ? .white.opacity(0.18) : settings.accentSoft, in: .circle)
                    .foregroundStyle(filled ? .white : settings.accent)

                Spacer(minLength: 24)

                Text(mode.title)
                    .kFont(46, .bold)
                    .tracking(-1)
                Text(mode == .borrow ? "Collect an item you've booked" : "Drop off an item you've borrowed")
                    .kFont(18, .medium)
                    .opacity(filled ? 0.85 : 1)
                    .foregroundStyle(filled ? .white : settings.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 6)

                HStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                    Text("Scan QR code")
                }
                .kFont(16, .semibold)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(filled ? .white.opacity(0.18) : settings.surface, in: .capsule)
                .padding(.top, 20)
            }
            .foregroundStyle(filled ? .white : settings.ink)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background {
                if filled {
                    RoundedRectangle(cornerRadius: 36)
                        .fill(settings.highContrast
                              ? AnyShapeStyle(settings.accent)
                              : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x3D5AFE), Color(hex: 0x7C4DFF)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .shadow(color: settings.accent.opacity(settings.highContrast ? 0 : 0.35), radius: 30, y: 16)
                } else {
                    RoundedRectangle(cornerRadius: 36)
                        .fill(.white)
                        .overlay(RoundedRectangle(cornerRadius: 36)
                            .strokeBorder(settings.highContrast ? settings.ink : settings.hairline,
                                          lineWidth: settings.highContrast ? 3 : 1.5))
                        .shadow(color: .black.opacity(settings.highContrast ? 0 : 0.05), radius: 30, y: 16)
                }
            }
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel("\(mode.title). Scan your booking QR code.")
    }
}

private struct ShortcutTile: View {
    @Environment(KioskSettings.self) private var settings
    let title: String
    let subtitle: String
    let symbol: String
    /// Needs sign in. Shows a lock instead of the chevron.
    var locked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                IconBadge(symbol: symbol, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).kFont(19, .semibold)
                    Text(subtitle).kFont(15).foregroundStyle(settings.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: locked ? "lock.fill" : "chevron.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(settings.secondary)
            }
            .foregroundStyle(settings.ink)
            .card(padding: 18)
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityHint(locked ? "Sign in required" : "")
    }
}
