import ActivityKit
import Foundation
import UIKit

@available(iOS 16.2, *)
final class RestActivityManager {
    static let shared = RestActivityManager()

    private var autoStopTask: Task<Void, Never>?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    private init() {
        // Если приложение развернули или разблокировали экран — сразу убираем просроченные 0:00
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

        autoStopTask?.cancel()
        endBackgroundTask()

        let duration = max(1.0, seconds)
        let now = Date()
        let end = now.addingTimeInterval(duration)
        let cleanName = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "РАБОЧИЙ ПОДХОД"
            : exerciseName

        // Просим у iOS фоновое время, чтобы таймер сам закрыл остров даже при заблокированном экране
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "FormRestTimerAutoStop") { [weak self] in
            self?.cleanupExpiredActivities()
            self?.endBackgroundTask()
        }

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
                // staleDate равен точному концу таймера без лишних +60 секунд
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

        // Автоматически закрываем остров ровно через duration секунд
        autoStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            for activity in Activity<RestActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            self?.endBackgroundTask()
        }
    }

    func stopActivity() {
        autoStopTask?.cancel()
        autoStopTask = nil
        endBackgroundTask()

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

    private func endBackgroundTask() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }
}
