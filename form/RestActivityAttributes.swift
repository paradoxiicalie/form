//
//  RestActivityAttributes.swift
//  form
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit

public struct RestActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var endTime: Date
        public var totalSeconds: Double
        public var exerciseName: String
        public var themeCalHex: String
        
        public init(endTime: Date, totalSeconds: Double, exerciseName: String, themeCalHex: String) {
            self.endTime = endTime
            self.totalSeconds = totalSeconds
            self.exerciseName = exerciseName
            self.themeCalHex = themeCalHex
        }
    }
    
    public var id: String
    
    public init(id: String = UUID().uuidString) {
        self.id = id
    }
}
#endif
