//
//  Community.swift
//  Nook
//

import Foundation

/// A resident signed in at the kiosk with their apartment number and PIN.
struct Resident: Identifiable, Hashable {
    let unit: String
    let firstName: String
    /// Building staff. Signing in as admin opens the admin screen.
    var isAdmin = false

    var id: String { unit }
    /// Apartment 1204 is on level 12. Shown instead of the full unit number
    /// so requests don't broadcast exactly where someone lives.
    var level: Int { Int(unit.dropLast(2)) ?? 0 }
    var publicName: String { "\(firstName) · Level \(level)" }
}

enum RequestReward: Hashable {
    case thanks
    case coffee
    case treat
    case cash(Int)

    var label: String {
        switch self {
        case .thanks: "A big thank you"
        case .coffee: "Coffee on me"
        case .treat: "Home-baked treat"
        case .cash(let amount): "$\(amount)"
        }
    }

    var symbol: String {
        switch self {
        case .thanks: "heart.fill"
        case .coffee: "cup.and.saucer.fill"
        case .treat: "birthday.cake.fill"
        case .cash: "dollarsign.circle.fill"
        }
    }

    static let options: [RequestReward] = [.thanks, .coffee, .treat, .cash(5), .cash(10), .cash(20)]
}

enum RequestStatus: Hashable {
    /// Up for grabs.
    case open
    case accepted(by: Resident)
    case completed
}

/// A favour a resident has asked the building for, e.g. "Water my plants".
/// Posted from the Nook app or the kiosk; any other resident can accept it.
struct CommunityRequest: Identifiable, Hashable {
    let id: UUID
    let title: String
    let details: String
    let symbol: String
    let requester: Resident
    let reward: RequestReward
    let postedAt: Date
    let neededBy: Date
    var status: RequestStatus

    var isOpen: Bool { status == .open }

    var helper: Resident? {
        if case .accepted(let by) = status { return by }
        return nil
    }
}

enum SignInProblem: Error {
    case wrongDetails
}
