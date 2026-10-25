import ActivityKit
import Foundation
import UIKit

@available(iOS 16.2, *)
final class RestActivityManager {
    static let shared = RestActivityManager()

    private init() {
        // При разблокировке или возврате в приложение очищаем завершенные активности
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cleanupExpiredActivities()
        }
    }

    func startActivity(
        seconds: Double,
        exerciseName: String,
        themeCalHex: String = "#D62828",
        onDisabled: (() -> Void)? = nil
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            onDisabled?()
            return
        }

        let duration = max(1.0, seconds)
        let now = Date()
        let end = now.addingTimeInterval(duration)
        let cleanName = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "РАБОЧИЙ ПОДХОД"
            : exerciseName

        Task { @MainActor in
            for activity in Activity<RestActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }

            let attributes = RestActivityAttributes(workoutTitle: "FORM // SYSTEM")
            let state = RestActivityAttributes.ContentState(
                startDate: now,
                endDate: end,
                exerciseName: cleanName,
                themeCalHex: themeCalHex
            )

            do {
                // staleDate равен концу таймера. Ровно на 0:00 виджет получает isStale == true
                let content = ActivityContent(state: state, staleDate: end)
                _ = try Activity<RestActivityAttributes>.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } catch {
                print("Ошибка запуска Live Activity: \(error.localizedDescription)")
            }
        }
    }

    func stopActivity() {
        Task { @MainActor in
            for activity in Activity<RestActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func cleanupExpiredActivities() {
        let now = Date()
        Task { @MainActor in
            for activity in Activity<RestActivityAttributes>.activities {
                if activity.content.state.endDate <= now {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }
}
