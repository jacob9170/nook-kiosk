//
//  ConfirmView.swift
//  Nook
//

import SwiftUI

struct ConfirmView: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    let booking: Booking
    let mode: KioskMode

    @State private var condition: ReturnCondition?

    private var canContinue: Bool { mode == .borrow || condition != nil }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 40)) : AnyLayout(VStackLayout(spacing: 28))
            layout {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        summary
                        if mode == .return { conditionPicker }
                    }
                    .padding(.vertical, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: .infinity)

                VStack(spacing: 24) {
                    LockerBankView(lockers: store.lockers, highlighted: booking.lockerNumber)
                    Text("Your item is in locker **\(booking.lockerLabel)**")
                        .kFont(20)
                        .foregroundStyle(settings.secondary)
                    Spacer(minLength: 0)
                    Button {
                        store.go(.locker(booking, mode, condition))
                    } label: {
                        Label("Open locker \(booking.lockerLabel)", systemImage: "lock.open.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canContinue)
                    .opacity(canContinue ? 1 : 0.4)
                    if !canContinue {
                        Text("Let us know how the item is first")
                            .kFont(16)
                            .foregroundStyle(settings.secondary)
                    }
                }
                .frame(maxWidth: wide ? geo.size.width * 0.4 : .infinity)
            }
        }
        .padding(.top, 8)
        .onAppear {
            settings.speak(mode == .borrow
                ? "Hi \(booking.residentFirstName). Your \(booking.item.name) is in locker \(booking.lockerNumber). Tap Open locker when you're ready."
                : "Thanks \(booking.residentFirstName). Tell us how the \(booking.item.name) is, then tap Open locker \(booking.lockerNumber).")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hi \(booking.residentFirstName) 👋")
                .kFont(22, .semibold)
                .foregroundStyle(settings.accent)
            Text(mode == .borrow ? "Ready to collect" : "Ready to return")
                .kFont(48, .bold)
                .tracking(-1)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 20) {
                IconBadge(symbol: booking.item.symbol, size: 84)
                VStack(alignment: .leading, spacing: 6) {
                    Text(booking.item.name).kFont(30, .bold)
                    Text(booking.item.blurb)
                        .kFont(17)
                        .foregroundStyle(settings.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider().overlay(settings.hairline)

            HStack(alignment: .top, spacing: 0) {
                Fact(label: "Locker", value: booking.lockerLabel)
                Fact(label: "Booking", value: booking.code)
                if mode == .borrow {
                    Fact(label: "Return by", value: booking.returnDue.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                } else {
                    Fact(label: booking.isOverdue ? "Was due" : "Due",
                         value: booking.returnDue.formatted(.dateTime.weekday(.abbreviated).hour().minute()),
                         tint: booking.isOverdue ? settings.danger : nil)
                }
            }

            if booking.isOverdue {
                Label("This return is overdue. No stress, thanks for bringing it back.", systemImage: "clock.badge.exclamationmark.fill")
                    .kFont(17, .medium)
                    .foregroundStyle(settings.danger)
            }
        }
        .card()
    }

    private var conditionPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How's the item?")
                .kFont(26, .bold)
            HStack(spacing: 14) {
                ForEach(ReturnCondition.allCases) { option in
                    let selected = condition == option
                    Button {
                        withAnimation(settings.animation) { condition = option }
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: option.symbol)
                                .font(.system(size: 30, weight: .semibold))
                            Text(option.rawValue)
                                .kFont(17, .semibold)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(selected ? .white : settings.ink)
                        .frame(maxWidth: .infinity, minHeight: 130)
                        .padding(12)
                        .background(selected ? settings.accent : settings.surface, in: .rect(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(settings.highContrast ? settings.ink : .clear, lineWidth: 2))
                    }
                    .buttonStyle(TileButtonStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

private struct Fact: View {
    @Environment(KioskSettings.self) private var settings
    let label: String
    let value: String
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .kFont(13, .bold)
                .tracking(1)
                .foregroundStyle(settings.secondary)
            Text(value)
                .kFont(24, .semibold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(tint ?? settings.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
