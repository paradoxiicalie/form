import ActivityKit
import AVFoundation
import Foundation
import UIKit

@available(iOS 16.2, *)
final class RestActivityManager {
    static let shared = RestActivityManager()

    private var autoStopTask: Task<Void, Never>?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var silentPlayer: AVAudioPlayer?

    private init() {
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
        stopSilentAudioKeepAlive()

        let duration = max(1.0, seconds)
        let now = Date()
        let end = now.addingTimeInterval(duration)
        let cleanName = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "РАБОЧИЙ ПОДХОД"
            : exerciseName

        // Держим процесс активным в фоне без влияния на Spotify / Apple Music
        startSilentAudioKeepAlive()
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

        // Ровно на 0:00 закрываем остров и выключаем фоновый держатель
        autoStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            for activity in Activity<RestActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            self?.stopSilentAudioKeepAlive()
            self?.endBackgroundTask()
        }
    }

    func stopActivity() {
        autoStopTask?.cancel()
        autoStopTask = nil
        stopSilentAudioKeepAlive()
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

    // MARK: - Бесшумный аудио-держатель для точного закрытия на 0:00
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
