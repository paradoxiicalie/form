import ActivityKit
import AppIntents
import Foundation
import UserNotifications
import WidgetKit

struct RestActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var startDate: Date
        var endDate: Date
        var exerciseName: String
        var themeCalHex: String

        init(
            startDate: Date = Date(),
            endDate: Date,
            exerciseName: String,
            themeCalHex: String = "#D62828"
        ) {
            self.startDate = startDate
            self.endDate = endDate
            self.exerciseName = exerciseName
            self.themeCalHex = themeCalHex
        }
    }

    var workoutTitle: String = "FORM // SYSTEM"
}

@available(iOS 16.2, *)
struct StopRestTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Сбросить таймер отдыха"

    func perform() async throws -> some IntentResult {
        for activity in Activity<RestActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["rest_timer", "form_rest_timer", "restNotification"]
        )

        if let d = UserDefaults(suiteName: "group.com.macro.shared") {
            d.set(0.0, forKey: "restTimerEndDate")
            d.set(true, forKey: "restTimerStoppedExternally")
            d.synchronize()
        }
        WidgetCenter.shared.reloadAllTimelines()

        await MainActor.run {
            NotificationCenter.default.post(
                name: Notification.Name("FormStopRestTimerExternally"),
                object: nil
            )
        }

        return .result()
    }
}
