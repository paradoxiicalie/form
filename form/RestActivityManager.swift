import ActivityKit
import AVFoundation
import Foundation
import UIKit

@available(iOS 16.2, *)
final class RestActivityManager {
    static let shared = RestActivityManager()

    private var lifecycleTask: Task<Void, Never>?
    private var operationGeneration: UInt64 = 0
    private var autoStopTask: Task<Void, Never>?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var silentPlayer: AVAudioPlayer?

    private init() {
        // При разблокировке или возврате в приложение очищаем завершенные активности
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cleanupExpiredActivities()
        }
        // Немедленная остановка keep-alive ресурсов и Live Activity по внешнему сигналу (например с LiveActivityIntent)
        NotificationCenter.default.addObserver(
            forName: Notification.Name("FormStopRestTimerExternally"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopActivity()
        }
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func startActivity(
        seconds: Double,
        totalSeconds: Double? = nil,
        exerciseName: String,
        themeCalHex: String = "#D62828",
        onDisabled: (() -> Void)? = nil
    ) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                onDisabled?()
                return
            }

            self.autoStopTask?.cancel()
            self.operationGeneration &+= 1
            let myGen = self.operationGeneration

            let duration = max(1.0, seconds)
            let now = Date()
            let end = now.addingTimeInterval(duration)
            let total = max(duration, totalSeconds ?? duration)
            let start = end.addingTimeInterval(-total)
            let cleanName = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "РАБОЧИЙ ПОДХОД"
                : exerciseName

            // Держим процесс активным в фоне без влияния на Spotify / Apple Music
            if self.silentPlayer == nil || self.silentPlayer?.isPlaying == false {
                self.startSilentAudioKeepAlive()
            }
            if self.bgTask == .invalid {
                self.bgTask = UIApplication.shared.beginBackgroundTask(withName: "FormRestTimerAutoStop") { [weak self] in
                    self?.cleanupExpiredActivities()
                    self?.endBackgroundTask()
                }
            }

            let previousTask = self.lifecycleTask
            self.lifecycleTask = Task { @MainActor [weak self] in
                _ = await previousTask?.result
                guard let self = self, !Task.isCancelled, self.operationGeneration == myGen else { return }

                let state = RestActivityAttributes.ContentState(
                    startDate: start,
                    endDate: end,
                    exerciseName: cleanName,
                    themeCalHex: themeCalHex
                )
                let content = ActivityContent(state: state, staleDate: end)

                let existing = Activity<RestActivityAttributes>.activities
                if let primary = existing.first(where: { $0.activityState == .active || $0.activityState == .stale }) ?? existing.first {
                    for extra in existing where extra.id != primary.id {
                        await extra.end(nil, dismissalPolicy: .immediate)
                    }
                    if primary.activityState == .active || primary.activityState == .stale {
                        await primary.update(content)
                        return
                    } else {
                        await primary.end(nil, dismissalPolicy: .immediate)
                    }
                }

                let attributes = RestActivityAttributes(workoutTitle: "FORM // SYSTEM")
                do {
                    _ = try Activity<RestActivityAttributes>.request(
                        attributes: attributes,
                        content: content,
                        pushType: nil
                    )
                } catch {
                    print("Ошибка запуска Live Activity: \(error.localizedDescription)")
                }
            }

            // На 0:00 корректно закрываем Dynamic Island и освобождаем keep-alive ресурсы
            self.autoStopTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((duration + 0.5) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.stopActivity()
            }
        }
    }

    func stopActivity() {
        runOnMain { [weak self] in
            guard let self = self else { return }
            self.autoStopTask?.cancel()
            self.autoStopTask = nil
            self.operationGeneration &+= 1
            let myGen = self.operationGeneration
            self.stopSilentAudioKeepAlive()
            self.endBackgroundTask()

            let previousTask = self.lifecycleTask
            self.lifecycleTask = Task { @MainActor [weak self] in
                _ = await previousTask?.result
                guard let self = self, self.operationGeneration == myGen else { return }
                for activity in Activity<RestActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }

    func cleanupExpiredActivities() {
        runOnMain { [weak self] in
            guard let self = self else { return }
            let now = Date()
            let previousTask = self.lifecycleTask
            self.lifecycleTask = Task { @MainActor [weak self] in
                _ = await previousTask?.result
                guard let self = self else { return }
                var hasActiveRemaining = false
                for activity in Activity<RestActivityAttributes>.activities {
                    if activity.content.state.endDate <= now {
                        await activity.end(nil, dismissalPolicy: .immediate)
                    } else if activity.activityState == .active {
                        hasActiveRemaining = true
                    }
                }
                if !hasActiveRemaining && self.autoStopTask == nil {
                    self.stopSilentAudioKeepAlive()
                    self.endBackgroundTask()
                }
            }
        }
    }

    // MARK: - Бесшумный аудио-держатель для точного закрытия острова на 0:00
    private func startSilentAudioKeepAlive() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let wavData = Self.makeSilentWavData()
            let player = try AVAudioPlayer(data: wavData)
            player.numberOfLoops = -1
            player.volume = 0.0
            player.prepareToPlay()
            player.play()
            self.silentPlayer = player
        } catch {
            print("Silent keep-alive error: \(error.localizedDescription)")
        }
    }

    private func stopSilentAudioKeepAlive() {
        silentPlayer?.stop()
        silentPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func makeSilentWavData() -> Data {
        let sampleRate: UInt32 = 8000
        let numSamples: UInt32 = 8000 // 1 секунда тишины
        let dataSize = numSamples * 2
        let fileSize = 36 + dataSize

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        data.append("WAVEfmt ".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // PCM
        data.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // Mono
        data.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: (sampleRate * 2).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(2).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(16).littleEndian) { Data($0) })
        data.append("data".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        data.append(Data(count: Int(dataSize)))
        return data
    }

    private func endBackgroundTask() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }
}
