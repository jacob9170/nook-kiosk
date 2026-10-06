//
//  RequestsView.swift
//  Nook
//

import SwiftUI

struct RequestsView: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings

    private enum Tab: Hashable { case open, active, mine }
    @State private var tab: Tab = .open
    @State private var working: UUID?

    private var inProgress: [CommunityRequest] {
        store.requests.filter { $0.helper != nil }
    }

    private var mine: [CommunityRequest] {
        guard let profile = store.profile else { return [] }
        return store.requests.filter { $0.requester == profile || $0.helper == profile }
    }

    private var shown: [CommunityRequest] {
        switch tab {
        case .open: store.openRequests
        case .active: inProgress
        case .mine: mine
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Neighbours need a hand")
                        .kFont(40, .bold)
                        .tracking(-1)
                    Text("Help out, earn a reward. Or ask the building for a favour.")
                        .kFont(19)
                        .foregroundStyle(settings.secondary)
                }
                Spacer()
                Button {
                    store.requireLogin("Sign in to post a request from your apartment.") { _ in
                        store.go(.newRequest)
                    }
                } label: {
                    Label("Post a request", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .fixedSize()
            }

            HStack(spacing: 10) {
                TabChip(title: "Up for grabs", count: store.openRequests.count, selected: tab == .open) { tab = .open }
                TabChip(title: "In progress", count: inProgress.count, selected: tab == .active) { tab = .active }
                if store.profile != nil {
                    TabChip(title: "Mine", count: mine.count, selected: tab == .mine) { tab = .mine }
                }
            }

            ScrollView {
                if shown.isEmpty {
                    empty
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340 * settings.textScale), spacing: 18, alignment: .top)],
                              spacing: 18) {
                        ForEach(shown) { request in
                            RequestCard(request: request, working: working == request.id,
                                        onAccept: { accept(request) },
                                        onDecline: { withAnimation(settings.animation) { store.decline(request) } })
                        }
                    }
                    .padding(.bottom, 12)
                    .animation(settings.animation, value: shown.map(\.id))
                }
            }
        }
        .padding(.top, 8)
        .onChange(of: store.profile) { _, profile in
            if profile == nil && tab == .mine { tab = .open }
        }
        .onAppear {
            settings.speak("\(store.openRequests.count) requests are up for grabs. Accept one to help a neighbour and earn a reward.")
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "hands.and.sparkles.fill")
                .font(.system(size: 48))
                .foregroundStyle(settings.accent)
            Text(tab == .open ? "Nothing up for grabs right now" : "Nothing here yet")
                .kFont(24, .semibold)
            Text("New requests from the Nook app show up here straight away.")
                .kFont(18)
                .foregroundStyle(settings.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private func accept(_ request: CommunityRequest) {
        store.requireLogin("Sign in so \(request.requester.firstName) knows who's helping.") { resident in
            guard resident != request.requester else {
                store.showToast("That's your own request")
                return
            }
            working = request.id
            Task {
                do {
                    try await store.accept(request, by: resident)
                    store.showToast("You're on it! \(request.requester.firstName) has been notified in the Nook app.")
                    settings.speak("You're on it. \(request.requester.firstName) has been notified.")
                } catch {
                    store.showToast("Someone else just grabbed that one")
                }
                working = nil
            }
        }
    }
}

private struct TabChip: View {
    @Environment(KioskSettings.self) private var settings
    let title: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title).kFont(18, .semibold)
                Text("\(count)")
                    .kFont(15, .bold, design: .rounded)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(selected ? .white.opacity(0.2) : settings.hairline, in: .capsule)
            }
            .padding(.horizontal, 22)
            .frame(height: 56)
            .foregroundStyle(selected ? .white : settings.ink)
            .background(selected ? settings.ink : settings.surface, in: .capsule)
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct RequestCard: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    let request: CommunityRequest
    let working: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                IconBadge(symbol: request.symbol, size: 56)
                Spacer()
                RewardBadge(reward: request.reward)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(request.title)
                    .kFont(23, .bold)
                    .fixedSize(horizontal: false, vertical: true)
                Text(request.details)
                    .kFont(16)
                    .foregroundStyle(settings.secondary)
                    .lineLimit(2, reservesSpace: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Meta(symbol: "person.fill", text: request.requester.publicName)
                Meta(symbol: "clock.fill", text: "Needed by \(neededBy)")
            }

            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 24)
    }

    @ViewBuilder
    private var footer: some View {
        if let helper = request.helper {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                Text(helper == store.profile ? "You're helping" : "\(helper.firstName) is on it")
            }
            .kFont(17, .semibold)
            .foregroundStyle(settings.success)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(settings.success.opacity(0.1), in: .capsule)
        } else if request.requester == store.profile {
            Text("Your request · waiting for a helper")
                .kFont(17, .semibold)
                .foregroundStyle(settings.secondary)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(settings.surface, in: .capsule)
        } else {
            HStack(spacing: 12) {
                Button("Decline", action: onDecline)
                    .buttonStyle(SecondaryButtonStyle())
                Button(action: onAccept) {
                    if working {
                        ProgressView().tint(.white)
                    } else {
                        Text("Accept")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(working)
            }
        }
    }

    private var neededBy: String {
        let cal = Calendar.current
        let time = request.neededBy.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(request.neededBy) { return "\(time) today" }
        if cal.isDateInTomorrow(request.neededBy) { return "\(time) tomorrow" }
        return request.neededBy.formatted(.dateTime.weekday(.wide).hour().minute())
    }
}

struct RewardBadge: View {
    @Environment(KioskSettings.self) private var settings
    let reward: RequestReward

    private var isCash: Bool {
        if case .cash = reward { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: reward.symbol)
            Text(reward.label)
        }
        .kFont(isCash ? 20 : 16, .bold, design: isCash ? .rounded : .default)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Capsule().fill(settings.highContrast
                ? AnyShapeStyle(isCash ? settings.success : settings.accent)
                : AnyShapeStyle(LinearGradient(colors: isCash ? [Color(hex: 0x12B76A), Color(hex: 0x0E9384)]
                                                               : [Color(hex: 0x3D5AFE), Color(hex: 0x7C4DFF)],
                                               startPoint: .leading, endPoint: .trailing)))
        }
        .accessibilityLabel("Reward: \(reward.label)")
    }
}

private struct Meta: View {
    @Environment(KioskSettings.self) private var settings
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 18)
            Text(text).kFont(16, .medium)
        }
        .foregroundStyle(settings.secondary)
    }
}
