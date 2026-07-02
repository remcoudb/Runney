//
//  Item.swift
//  Runney
//
//  Created by Remco Uitdenboogaart on 02/07/2026.
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
