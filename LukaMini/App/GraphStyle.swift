//
//  GraphStyle.swift
//  LukaMini
//

import Foundation

enum GraphStyle: String, CaseIterable, Identifiable {
    var id: Self { self }

    case line
    case dots
}
