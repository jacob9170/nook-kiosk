//
//  AvailableView.swift
//  Nook
//

import SwiftUI

struct AvailableView: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    @State private var category: ItemCategory?
    @State private var selected: Locker?
    /// Set when "Book now" is tapped, so we can sign in once the sheet has closed.
    @State private var toBook: Locker?

    private var filtered: [Locker] {
        store.lockers.filter { $0.item != nil && (category == nil || $0.item?.category == category) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(store.availableCount) of \(store.lockers.count) ready to borrow")
                        .kFont(40, .bold)
                        .tracking(-1)
                    Text("Book any item in the Nook app, then scan here to collect.")
                        .kFont(19)
                        .foregroundStyle(settings.secondary)
                }
                Spacer()
                legend
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Chip(title: "All", symbol: "square.grid.2x2", selected: category == nil) { category = nil }
                    ForEach(ItemCategory.allCases) { c in
                        Chip(title: c.rawValue, symbol: c.symbol, selected: category == c) { category = c }
                    }
                }
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260 * settings.textScale), spacing: 18)], spacing: 18) {
                    ForEach(filtered) { locker in
                        LockerCard(locker: locker) { selected = locker }
                    }
                }
                .padding(.bottom, 12)
                .animation(settings.animation, value: category)
            }
        }
        .padding(.top, 8)
        .sheet(item: $selected, onDismiss: bookIfNeeded) { locker in
            LockerDetail(locker: locker) {
                toBook = locker
                selected = nil
            }
                .environment(settings)
                .presentationDetents([.medium])
        }
        .onAppear {
            settings.speak("\(store.availableCount) items are ready to borrow. Book them in the Nook app, or sign in here.")
        }
    }

    private func bookIfNeeded() {
        guard let locker = toBook, let item = locker.item else { return }
        toBook = nil
        store.requireLogin("Sign in to book the \(item.name) to your apartment.") { resident in
            Task {
                do {
                    let booking = try await store.bookNow(locker, for: resident)
                    store.go(.confirm(booking, .borrow))
                } catch {
                    store.showToast("Sorry, that item was just booked by someone else")
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 18) {
            ForEach([LockerStatus.available, .reserved, .onLoan, .maintenance], id: \.self) { status in
                HStack(spacing: 6) {
                    Circle().fill(settings.color(for: status)).frame(width: 10, height: 10)
                    Text(status.rawValue).kFont(15, .medium).foregroundStyle(settings.secondary)
                }
            }
        }
    }
}

private struct Chip: View {
    @Environment(KioskSettings.self) private var settings
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .kFont(18, .semibold)
                .padding(.horizontal, 22)
                .frame(height: 56)
                .foregroundStyle(selected ? .white : settings.ink)
                .background(selected ? settings.ink : settings.surface, in: .capsule)
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct LockerCard: View {
    @Environment(KioskSettings.self) private var settings
    let locker: Locker
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    IconBadge(symbol: locker.item?.symbol ?? "questionmark", size: 60)
                    Spacer()
                    Text(locker.label)
                        .kFont(20, .bold, design: .rounded)
                        .foregroundStyle(settings.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(locker.item?.name ?? "Empty")
                        .kFont(22, .semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(locker.item?.category.rawValue ?? "")
                        .kFont(16)
                        .foregroundStyle(settings.secondary)
                }
                StatusPill(text: locker.status.rawValue, color: settings.color(for: locker.status))
            }
            .foregroundStyle(settings.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 22)
            .opacity(locker.status == .available ? 1 : 0.7)
        }
        .buttonStyle(TileButtonStyle())
    }
}

private struct LockerDetail: View {
    @Environment(KioskSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    let locker: Locker
    let onBook: () -> Void

    var body: some View {
        if let item = locker.item {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 20) {
                    IconBadge(symbol: item.symbol, size: 88)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name).kFont(34, .bold)
                        Text("Locker \(locker.label) · \(locker.size.rawValue) · \(item.category.rawValue)")
                            .kFont(18)
                            .foregroundStyle(settings.secondary)
                    }
                    Spacer()
                    StatusPill(text: locker.status.rawValue, color: settings.color(for: locker.status))
                }
                Text(item.blurb).kFont(20)
                Label("Borrow for up to \(item.maxLoanDays) days", systemImage: "calendar.badge.clock")
                    .kFont(18, .medium)
                    .foregroundStyle(settings.secondary)
                Label(locker.status == .available
                      ? "Book it here, or in the Nook app and scan your QR code."
                      : "Not available right now. Check the Nook app for the next free slot.",
                      systemImage: "iphone.gen3")
                    .kFont(18, .medium)
                    .foregroundStyle(settings.accent)
                Spacer()
                HStack(spacing: 14) {
                    Button("Close") { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                    if locker.status == .available {
                        Button(action: onBook) {
                            Label("Book & collect now", systemImage: "lock.open.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
            .foregroundStyle(settings.ink)
            .padding(40)
        }
    }
}
