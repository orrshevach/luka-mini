//
//  Color+Extensions.swift
//  LukaMini
//

import SwiftUI

extension Color {
    static var lowColor: Color {
        Color.pink.mix(with: .red, by: 0.5)
    }
    static var inRangeColor: Color {
        Color.mint.mix(with: .green, by: 0.5)
    }
    static var highColor: Color {
        Color.yellow.mix(with: .orange, by: 0.5)
    }
}
