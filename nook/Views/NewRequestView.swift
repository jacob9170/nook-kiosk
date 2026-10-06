//
//  NewRequestView.swift
//  Nook
//

import SwiftUI

struct NewRequestView: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings

    private enum Deadline: String, CaseIterable, Identifiable {
        case hour = "Within the hour"
        case today = "Later today"
        case tomorrow = "Tomorrow"
        case week = "This week"

        var id: String { rawValue }

        var date: Date {
            let cal = Calendar.current
            switch self {
            case .hour: return .now.addingTimeInterval(3600)
            case .today:
                let evening = cal.date(bySettingHour: 20, minute: 0, second: 0, of: .now)!
                return max(evening, .now.addingTimeInterval(2 * 3600))
            case .tomorrow:
                return cal.date(bySettingHour: 18, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: .now)!)!
            case .week:
                return cal.date(byAdding: .day, value: 6, to: .now)!
            }
        }
    }

    @State private var title = ""
    @State private var details = ""
    @State private var reward: RequestReward = .coffee
    @State private var deadline: Deadline = .today
    @State private var posting = false
    @FocusState private var focused: Bool

    private let ideas = ["Water my plants", "Collect a parcel", "Walk my dog", "Help moving furniture", "Borrow a charger"]

    private var canPost: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && !posting }

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ask for a favour")
                            .kFont(40, .bold)
                            .tracking(-1)
                        if let profile = store.profile {
                            Text("Posting as \(profile.publicName). Neighbours won't see your apartment number.")
                                .kFont(18)
                                .foregroundStyle(settings.secondary)
                        }
                    }

                    FormSection(title: "What do you need?") {
                        TextField("e.g. Water my plants", text: $title)
                            .kFont(24, .semibold)
                            .focused($focused)
                            .submitLabel(.done)
                            .padding(22)
                            .background(settings.surface, in: .rect(cornerRadius: 20))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(ideas, id: \.self) { idea in
                                    Choice(title: idea, selected: title == idea) { title = idea }
                                }
                            }
                        }
                    }

                    FormSection(title: "Any details? (optional)") {
                        TextField("Where, when, anything helpful", text: $details, axis: .vertical)
                            .kFont(19)
                            .lineLimit(2...4)
                            .padding(22)
                            .background(settings.surface, in: .rect(cornerRadius: 20))
                    }

                    FormSection(title: "Reward") {
                        FlowRow {
                            ForEach(RequestReward.options, id: \.self) { option in
                                Choice(title: option.label, symbol: option.symbol, selected: reward == option) { reward = option }
                            }
                        }
                    }

                    FormSection(title: "Needed by") {
                        FlowRow {
                            ForEach(Deadline.allCases) { option in
                                Choice(title: option.rawValue, selected: deadline == option) { deadline = option }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(alignment: .leading, spacing: 20) {
                Text("PREVIEW")
                    .kFont(13, .bold)
                    .tracking(1)
                    .foregroundStyle(settings.secondary)
                VStack(alignment: .leading, spacing: 14) {
                    RewardBadge(reward: reward)
                    Text(title.isEmpty ? "Your request" : title)
                        .kFont(24, .bold)
                        .foregroundStyle(title.isEmpty ? settings.secondary : settings.ink)
                    if !details.isEmpty {
                        Text(details).kFont(16).foregroundStyle(settings.secondary).lineLimit(3)
                    }
                    Label(deadline.rawValue, systemImage: "clock.fill")
                        .kFont(16, .medium)
                        .foregroundStyle(settings.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 24)

                Text("Your request goes live on the kiosk and in the Nook app. We'll notify you when someone accepts.")
                    .kFont(16)
                    .foregroundStyle(settings.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button {
                    post()
                } label: {
                    if posting {
                        ProgressView().tint(.white)
                    } else {
                        Label("Post request", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canPost)
                .opacity(canPost ? 1 : 0.4)
            }
            .frame(width: 360)
        }
        .padding(.top, 8)
        .onAppear {
            if store.profile == nil { store.go(.requests) }
            settings.speak("What do you need a hand with? Type your request, pick a reward, then tap Post request.")
        }
    }

    private func post() {
        guard let profile = store.profile, canPost else { return }
        focused = false
        posting = true
        Task {
            try? await store.post(title: title.trimmingCharacters(in: .whitespaces), details: details,
                                  reward: reward, neededBy: deadline.date, by: profile)
            store.showToast("Request posted. We'll let you know when someone accepts.")
            store.go(.requests)
        }
    }
}

private struct FormSection<Content: View>: View {
    @Environment(KioskSettings.self) private var settings
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).kFont(20, .bold)
            content
        }
    }
}

private struct Choice: View {
    @Environment(KioskSettings.self) private var settings
    let title: String
    var symbol: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .kFont(17, .semibold)
            .padding(.horizontal, 20)
            .frame(height: 54)
            .foregroundStyle(selected ? .white : settings.ink)
            .background(selected ? settings.accent : settings.surface, in: .capsule)
            .overlay(Capsule().strokeBorder(settings.highContrast && !selected ? settings.ink : .clear, lineWidth: 2))
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Lays children out left to right, wrapping onto new lines.
private struct FlowRow: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
