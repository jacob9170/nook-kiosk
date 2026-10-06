//
//  HelpView.swift
//  Nook
//

import SwiftUI

struct HelpView: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    @State private var reported: String?

    private let issues: [(String, String)] = [
        ("A locker won't open", "lock.trianglebadge.exclamationmark.fill"),
        ("A door won't close", "door.left.hand.open"),
        ("The item is damaged or missing", "shippingbox.and.arrow.backward.fill"),
        ("My QR code won't scan", "qrcode"),
        ("Something else", "ellipsis.bubble.fill"),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 20) {
                Text("What's going on?")
                    .kFont(44, .bold)
                    .tracking(-1)
                Text("Tap an issue and we'll let the building manager know straight away.")
                    .kFont(20)
                    .foregroundStyle(settings.secondary)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(issues, id: \.0) { title, symbol in
                            Button {
                                Task { await store.reportIssue(title) }
                                withAnimation(settings.animation) { reported = title }
                                settings.speak("Thanks. We've let the building manager know.")
                            } label: {
                                HStack(spacing: 18) {
                                    IconBadge(symbol: symbol, size: 52)
                                    Text(title).kFont(20, .semibold)
                                    Spacer()
                                    Image(systemName: reported == title ? "checkmark.circle.fill" : "chevron.right")
                                        .font(.system(size: reported == title ? 26 : 16, weight: .bold))
                                        .foregroundStyle(reported == title ? settings.success : settings.secondary)
                                }
                                .foregroundStyle(settings.ink)
                                .card(padding: 16)
                            }
                            .buttonStyle(TileButtonStyle())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 20) {
                if let reported {
                    VStack(alignment: .leading, spacing: 12) {
                        StatusPill(text: "Reported", color: settings.success)
                        Text("Thanks for letting us know")
                            .kFont(26, .bold)
                        Text("“\(reported)” has been sent to the building manager. You don't need to do anything else.")
                            .kFont(18)
                            .foregroundStyle(settings.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .card()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                VStack(alignment: .leading, spacing: 16) {
                    Label("Building manager", systemImage: "person.crop.circle.fill")
                        .kFont(20, .bold)
                    ContactRow(symbol: "phone.fill", text: "(02) 9000 1234")
                    ContactRow(symbol: "envelope.fill", text: "hub@thearden.com.au")
                    ContactRow(symbol: "clock.fill", text: "Mon–Fri, 8am – 6pm")
                    Divider().overlay(settings.hairline)
                    Label("After hours emergencies: call building security on (02) 9000 5678.", systemImage: "exclamationmark.shield.fill")
                        .kFont(16)
                        .foregroundStyle(settings.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card()
            }
            .frame(width: 400)
        }
        .padding(.top, 8)
        .onAppear { settings.speak("Help. Tap the problem you're having and we'll let the building manager know.") }
    }
}

private struct ContactRow: View {
    @Environment(KioskSettings.self) private var settings
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .foregroundStyle(settings.accent)
                .frame(width: 24)
            Text(text).kFont(18, .medium)
        }
    }
}
