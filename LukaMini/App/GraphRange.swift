//
//  GraphRange.swift
//  LukaMini
//

import Foundation

enum GraphRange: String, CaseIterable, Identifiable {
    var id: Self { self }

    case oneHour
    case threeHours
    case sixHours
    case eightHours
    case twelveHours
    case sixteenHours
    case twentyFourHours

    private var hours: Int {
        switch self {
        case .oneHour: 1
        case .threeHours: 3
        case .sixHours: 6
        case .eightHours: 8
        case .twelveHours: 12
        case .sixteenHours: 16
        case .twentyFourHours: 24
        }
    }

    var timeInterval: TimeInterval {
        60 * 60 * TimeInterval(hours)
    }

    var abbreviatedName: String {
        "\(hours)ʜ"
    }
}
