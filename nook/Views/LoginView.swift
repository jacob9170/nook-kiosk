//
//  LoginView.swift
//  Nook
//

import SwiftUI

/// Apartment number + PIN sign in. Only shown when someone does something
/// tied to their profile, like booking or posting a request.
struct LoginView: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    let prompt: LoginPrompt

    private enum Field { case unit, pin }
    @State private var field: Field = .unit
    @State private var unit = ""
    @State private var pin = ""
    @State private var checking = false
    @State private var failed = false
    @State private var shake = 0

    private let pinLength = 4

    var body: some View {
        GeometryReader { geo in
            let portrait = geo.size.height > geo.size.width
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { cancel() }

                Group {
                    if portrait {
                        VStack(alignment: .leading, spacing: 24) {
                            header
                            fields
                            NumberPad(keySize: CGSize(width: 120, height: 80)) { press($0) }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            actions
                        }
                        .frame(width: min(geo.size.width - 48, 620))
                    } else {
                        HStack(alignment: .center, spacing: 48) {
                            VStack(alignment: .leading, spacing: 24) {
                                header
                                fields
                                Spacer(minLength: 0)
                                actions
                            }
                            .frame(width: 400)
                            NumberPad(keySize: CGSize(width: 100, height: 78)) { press($0) }
                        }
                        .fixedSize()
                    }
                }
                .padding(portrait ? 36 : 44)
                .background {
                    RoundedRectangle(cornerRadius: 36)
                        .fill(.white)
                        .shadow(color: .black.opacity(0.12), radius: 40, y: 20)
                }
                .overlay(RoundedRectangle(cornerRadius: 36).strokeBorder(settings.hairline, lineWidth: settings.hairlineWidth))
                .modifier(Shake(amount: CGFloat(shake)))
                .animation(settings.reduceMotion ? nil : .default, value: shake)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear { settings.speak("Sign in with your apartment number and PIN.") }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            IconBadge(symbol: "person.crop.circle.fill", size: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text("Sign in")
                    .kFont(40, .bold)
                    .tracking(-1)
                Text(prompt.reason)
                    .kFont(18)
                    .foregroundStyle(settings.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldBox(label: "Apartment", value: unit, placeholder: "e.g. 1204",
                     active: field == .unit) { field = .unit }
            FieldBox(label: "PIN", value: String(repeating: "●", count: pin.count), placeholder: "4 digits",
                     active: field == .pin) { if !unit.isEmpty { field = .pin } }

            if failed {
                Label("That apartment number and PIN don't match.", systemImage: "exclamationmark.circle.fill")
                    .kFont(17, .semibold)
                    .foregroundStyle(settings.danger)
            }

            Text("Forgot your PIN? Reset it in the Nook app.")
                .kFont(15)
                .foregroundStyle(settings.secondary)

            #if DEBUG
            Text("Demo: apartment 1204, PIN 1234")
                .kFont(14, .medium, design: .monospaced)
                .foregroundStyle(settings.secondary)
            #endif
        }
    }

    private var actions: some View {
        HStack(spacing: 14) {
            Button("Cancel") { cancel() }
                .buttonStyle(SecondaryButtonStyle())
            Button {
                advance()
            } label: {
                if checking {
                    ProgressView().tint(.white)
                } else {
                    Text(field == .unit ? "Next" : "Sign in")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canAdvance || checking)
            .opacity(canAdvance ? 1 : 0.4)
        }
    }

    private var canAdvance: Bool {
        field == .unit ? !unit.isEmpty : pin.count == pinLength
    }

    private func press(_ key: String) {
        failed = false
        switch (field, key) {
        case (.unit, "delete"): if !unit.isEmpty { unit.removeLast() }
        case (.unit, "clear"): unit = ""
        case (.unit, _): if unit.count < 4 { unit.append(key) }
        case (.pin, "delete"): if pin.isEmpty { field = .unit } else { pin.removeLast() }
        case (.pin, "clear"): pin = ""
        case (.pin, _):
            guard pin.count < pinLength else { return }
            pin.append(key)
            if pin.count == pinLength { advance() }
        }
    }

    private func advance() {
        guard canAdvance else { return }
        if field == .unit {
            field = .pin
            return
        }
        checking = true
        Task {
            do {
                let resident = try await store.signIn(unit: unit, pin: pin)
                store.loginPrompt = nil
                if resident.isAdmin {
                    // Staff always land on the admin screen.
                    store.showToast("Admin mode")
                    store.go(.admin)
                    return
                }
                store.showToast("Welcome back, \(resident.firstName)")
                settings.speak("Welcome back, \(resident.firstName).")
                prompt.onSuccess(resident)
            } catch {
                checking = false
                failed = true
                pin = ""
                shake += 1
                settings.speak("That apartment number and PIN don't match. Please try again.")
            }
        }
    }

    private func cancel() {
        store.loginPrompt = nil
    }
}

private struct FieldBox: View {
    @Environment(KioskSettings.self) private var settings
    let label: String
    let value: String
    let placeholder: String
    let active: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label.uppercased())
                    .kFont(13, .bold)
                    .tracking(1)
                    .foregroundStyle(active ? settings.accent : settings.secondary)
                Text(value.isEmpty ? placeholder : value)
                    .kFont(30, .semibold, design: .rounded)
                    .foregroundStyle(value.isEmpty ? settings.secondary.opacity(0.5) : settings.ink)
                    .tracking(value.hasPrefix("●") ? 6 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(settings.surface, in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20)
                .strokeBorder(active ? settings.accent : .clear, lineWidth: 3))
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel("\(label), \(value.isEmpty ? "empty" : label == "PIN" ? "\(value.count) digits" : value)")
    }
}

private struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 12 * sin(amount * .pi * 4), y: 0))
    }
}
