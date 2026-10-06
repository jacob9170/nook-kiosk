//
//  Models.swift
//  Nook
//

import Foundation

enum ItemCategory: String, CaseIterable, Identifiable {
    case tools = "Tools"
    case kitchen = "Kitchen"
    case outdoors = "Outdoors"
    case home = "Home"
    case leisure = "Leisure"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .tools: "wrench.and.screwdriver.fill"
        case .kitchen: "fork.knife"
        case .outdoors: "tent.fill"
        case .home: "sofa.fill"
        case .leisure: "gamecontroller.fill"
        }
    }
}

struct Item: Identifiable, Hashable {
    let id: String
    let name: String
    let category: ItemCategory
    let symbol: String
    let blurb: String
    let maxLoanDays: Int
}

enum LockerSize: String {
    case small = "S", medium = "M", large = "L"
}

enum LockerStatus: String {
    case available = "Available"
    case reserved = "Reserved"
    case onLoan = "On loan"
    case maintenance = "Maintenance"
}

struct Locker: Identifiable, Hashable {
    let number: Int
    let size: LockerSize
    var item: Item?
    var status: LockerStatus
    /// Whether the door is currently unlocked.
    var isUnlocked = false

    var id: Int { number }
    var label: String { String(format: "%02d", number) }
}

enum BookingStatus {
    /// Booked in the resident app, waiting to be collected.
    case reserved
    /// Collected from the locker, not yet returned.
    case onLoan
    case returned
    case cancelled
}

struct Booking: Identifiable, Hashable {
    /// Six-digit booking number. Encoded in the QR code the resident app generates.
    let code: String
    let residentFirstName: String
    let unit: String
    let item: Item
    let lockerNumber: Int
    let pickupStart: Date
    let pickupEnd: Date
    var returnDue: Date
    var status: BookingStatus

    var id: String { code }
    var lockerLabel: String { String(format: "%02d", lockerNumber) }
    var isOverdue: Bool { status == .onLoan && Date.now > returnDue }
}

enum KioskMode: Hashable {
    case borrow, `return`

    var title: String { self == .borrow ? "Borrow" : "Return" }
    var verb: String { self == .borrow ? "collect" : "return" }
}

enum ReturnCondition: String, CaseIterable, Identifiable {
    case good = "All good"
    case needsAttention = "Needs a clean"
    case damaged = "Damaged or missing parts"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .good: "hand.thumbsup.fill"
        case .needsAttention: "sparkles"
        case .damaged: "exclamationmark.triangle.fill"
        }
    }
}

/// Why a scanned booking can't be used right now.
enum BookingProblem: Error, Equatable {
    case notFound
    case tooEarly(opensAt: Date)
    case expired
    case alreadyCollected
    case notCollectedYet
    case alreadyReturned
    case cancelled
    case lockerFault

    var title: String {
        switch self {
        case .notFound: "We couldn't find that booking"
        case .tooEarly: "It's a little early"
        case .expired: "This pickup window has passed"
        case .alreadyCollected: "This item is already with you"
        case .notCollectedYet: "This item hasn't been collected yet"
        case .alreadyReturned: "This booking is complete"
        case .cancelled: "This booking was cancelled"
        case .lockerFault: "That locker needs attention"
        }
    }

    var message: String {
        switch self {
        case .notFound:
            "Check the booking number in the Nook app and try again."
        case .tooEarly(let opensAt):
            "Your pickup window opens at \(opensAt.formatted(date: .omitted, time: .shortened)). Come back then."
        case .expired:
            "Rebook the item in the Nook app to get a new pickup window."
        case .alreadyCollected:
            "Looks like you want to return it. Use this same QR code to return."
        case .notCollectedYet:
            "Looks like you want to borrow it. Use this same QR code to collect."
        case .alreadyReturned:
            "This item has already been returned. Thanks!"
        case .cancelled:
            "Make a new booking in the Nook app."
        case .lockerFault:
            "The building manager has been notified. Please try again later."
        }
    }

    /// The flow the resident probably meant, if they picked the wrong one.
    var suggestedMode: KioskMode? {
        switch self {
        case .alreadyCollected: .return
        case .notCollectedYet: .borrow
        default: nil
        }
    }
}
