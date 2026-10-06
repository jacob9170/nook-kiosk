//
//  LockerOpenView.swift
//  Nook
//

import SwiftUI

struct LockerOpenView: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    let booking: Booking
    let mode: KioskMode
    let condition: ReturnCondition?

    private enum Phase { case unlocking, open, finishing, failed }
    @State private var phase: Phase = .unlocking
    @State private var openedAt = Date.now

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            let layout = wide ? AnyLayout(HStackLayout(spacing: 48)) : AnyLayout(VStackLayout(spacing: 32))
            layout {
                LockerBankView(lockers: store.lockers, highlighted: booking.lockerNumber, doorOpen: phase == .open || phase == .finishing)
                    .frame(maxWidth: wide ? geo.size.width * 0.45 : 520)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 28) {
                    switch phase {
                    case .unlocking: unlockingPanel
                    case .open, .finishing: openPanel
                    case .failed: failedPanel
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .task { await unlock() }
    }

    private var unlockingPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            ProgressView().controlSize(.extraLarge).tint(settings.accent)
            Text("Unlocking locker \(booking.lockerLabel)…")
                .kFont(44, .bold)
                .tracking(-1)
            Text("Stand clear of the door.")
                .kFont(20)
                .foregroundStyle(settings.secondary)
        }
    }

    private var openPanel: some View {
        VStack(alignment: .leading, spacing: 28) {
            StatusPill(text: "Locker \(booking.lockerLabel) is open", color: settings.success)
            Text(mode == .borrow ? "Grab your\n\(booking.item.name)" : "Pop the \(booking.item.name) back in")
                .kFont(52, .bold)
                .tracking(-1.5)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 16) {
                Instruction(symbol: "arrow.up.left.and.arrow.down.right", text: "Door **\(booking.lockerLabel)** is highlighted on the map")
                Instruction(symbol: mode == .borrow ? "hand.raised.fill" : "shippingbox.fill",
                            text: mode == .borrow ? "Check everything is there" : "Include all parts and chargers")
                Instruction(symbol: "door.left.hand.closed", text: "Close the door firmly until it clicks")
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = Int(context.date.timeIntervalSince(openedAt))
                Text("Open for \(elapsed / 60):\(String(format: "%02d", elapsed % 60))")
                    .kFont(16, .medium)
                    .monospacedDigit()
                    .foregroundStyle(elapsed > 120 ? settings.warning : settings.secondary)
            }

            Spacer(minLength: 0)

            Button {
                Task { await finish() }
            } label: {
                if phase == .finishing {
                    ProgressView().tint(.white)
                } else {
                    Label("I've closed the door", systemImage: "checkmark")
                }
            }
            .buttonStyle(PrimaryButtonStyle(tint: settings.success))
            .disabled(phase == .finishing)

            Button("Something's wrong") {
                Task { await store.reportIssue("Problem at open locker", locker: booking.lockerNumber) }
                store.go(.help)
            }
            .kFont(18, .semibold)
            .foregroundStyle(settings.secondary)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            settings.speak(mode == .borrow
                ? "Locker \(booking.lockerNumber) is open. Take your \(booking.item.name), then close the door and tap I've closed the door."
                : "Locker \(booking.lockerNumber) is open. Place the \(booking.item.name) inside, close the door, and tap I've closed the door.")
        }
    }

    private var failedPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            IconBadge(symbol: "lock.trianglebadge.exclamationmark.fill", tint: settings.danger, size: 76)
            Text(BookingProblem.lockerFault.title)
                .kFont(44, .bold)
                .tracking(-1)
            Text(BookingProblem.lockerFault.message)
                .kFont(20)
                .foregroundStyle(settings.secondary)
            HStack(spacing: 16) {
                Button("Try again") {
                    phase = .unlocking
                    Task { await unlock() }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Back to start") { store.goHome() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 12)
        }
        .onAppear { settings.speak("Sorry, that locker didn't open. The building manager has been notified.") }
    }

    private func unlock() async {
        do {
            try await store.unlock(booking)
            openedAt = .now
            withAnimation(settings.animation) { phase = .open }
        } catch {
            await store.reportIssue("Locker failed to open", locker: booking.lockerNumber)
            withAnimation(settings.animation) { phase = .failed }
        }
    }

    private func finish() async {
        phase = .finishing
        await store.complete(booking, mode: mode, condition: condition)
        store.go(.done(booking, mode))
    }
}

private struct Instruction: View {
    @Environment(KioskSettings.self) private var settings
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(settings.accent)
                .frame(width: 44, height: 44)
                .background(settings.accentSoft, in: .circle)
            Text(text).kFont(20)
        }
    }
}
