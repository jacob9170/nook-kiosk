//
//  Admin.swift
//  Nook
//

import Foundation

enum TicketStatus: String, CaseIterable, Identifiable {
    case open = "Open"
    case inProgress = "In progress"
    case resolved = "Resolved"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .open: "exclamationmark.circle.fill"
        case .inProgress: "wrench.adjustable.fill"
        case .resolved: "checkmark.circle.fill"
        }
    }
}

/// A repair or service job, raised from the kiosk Help screen, a damaged
/// return, or by building staff.
struct ServiceTicket: Identifiable, Hashable {
    let id: UUID
    var lockerNumber: Int?
    var title: String
    var details: String
    var reportedBy: String
    let createdAt: Date
    var updatedAt: Date
    var status: TicketStatus

    var lockerLabel: String? { lockerNumber.map { String(format: "%02d", $0) } }
}

struct HubHours: Hashable {
    var openHour = 6
    var closeHour = 23
    var pickupWindowMinutes = 60

    static func label(_ hour: Int) -> String {
        switch hour {
        case 0, 24: "12am"
        case 12: "12pm"
        case 1..<12: "\(hour)am"
        default: "\(hour - 12)pm"
        }
    }

    var summary: String { "Open \(Self.label(openHour)) – \(Self.label(closeHour)) daily" }
    var windowSummary: String {
        pickupWindowMinutes % 60 == 0
            ? "\(pickupWindowMinutes / 60)-hour pickup windows"
            : "\(pickupWindowMinutes)-minute pickup windows"
    }
}

enum AdminCatalog {
    /// Icons staff can pick from when adding an item.
    static let symbols = [
        "wrench.and.screwdriver.fill", "hammer.fill", "stairs", "shower.handheld.fill",
        "birthday.cake.fill", "fork.knife", "cup.and.saucer.fill", "frying.pan.fill",
        "tent.fill", "basket.fill", "bicycle", "figure.hiking",
        "dice.fill", "gamecontroller.fill", "videoprojector.fill", "hifispeaker.fill",
        "bed.double.fill", "scissors", "bubbles.and.sparkles.fill", "shippingbox.fill",
    ]

    static let repairReasons = [
        "Door won't open", "Door won't close", "Item damaged", "Item missing parts",
        "Needs cleaning", "Battery or charger issue",
    ]
}
