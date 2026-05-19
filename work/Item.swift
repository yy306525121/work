//
//  Item.swift
//  work
//
//  Created by 杨忠洋 on 2026/5/19.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
