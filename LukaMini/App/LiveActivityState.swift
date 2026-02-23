//
//  LiveActivityState.swift
//  LukaMini
//

import Foundation
import Dexcom

enum LiveActivityState {
    struct Reading: Codable, Hashable {
        /// timestamp
        var t: Date
        /// value
        var v: Int16
    }
}

extension [GlucoseReading] {
    func toLiveActivityReadings() -> [LiveActivityState.Reading] {
        map { .init(t: $0.date, v: Int16($0.value)) }
    }
}
