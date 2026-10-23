//
//  RestActivityManager.swift
//  form
//

import Foundation
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

final class RestActivityManager {
    static let shared = RestActivityManager()
    private init() {}
    
    func startActivity(seconds: Double, exerciseName: String, themeCalHex: String) {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            // Проверяем поддержку Live Activities на устройстве
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                print("Live Activities are not enabled or supported on this device")
                return
            }
            
            // Завершаем предыдущие активные таймеры
            stopActivity()
            
            let future = Date().addingTimeInterval(max(1.0, seconds))
            let attributes = RestActivityAttributes(id: UUID().uuidString)
            let state = RestActivityAttributes.ContentState(
                endTime: future,
                totalSeconds: seconds,
                exerciseName: exerciseName.isEmpty ? "Подход" : exerciseName,
                themeCalHex: themeCalHex
            )
            
            do {
                let content = ActivityContent(state: state, staleDate: future.addingTimeInterval(10))
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
                print("Rest Activity successfully started for \(seconds)s, target: \(exerciseName)")
            } catch {
                print("Failed to start Rest Activity: \(error.localizedDescription)")
            }
        }
        #endif
    }
    
    func stopActivity() {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            Task {
                for activity in Activity<RestActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
        #endif
    }
}
