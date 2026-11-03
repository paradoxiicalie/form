import SwiftUI
import WebKit
import WidgetKit
import UserNotifications
import CoreMotion
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
#if canImport(ActivityKit)
import ActivityKit
#endif

final class WebViewModel {
    static let shared = WebViewModel()
    weak var webView: WKWebView?
    var pendingRoute: String?
    
    func navigate(to route: String) {
        if let wv = webView {
            wv.evaluateJavaScript("switchMainView('\(route)');", completionHandler: nil)
        } else {
            pendingRoute = route
        }
    }
}

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.identifier == "form_rest_timer" {
            if #available(iOS 16.2, *) {
                RestActivityManager.shared.stopActivity()
            }
        }
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .list])
        } else {
            completionHandler([.alert, .sound])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier == "form_rest_timer" {
            if #available(iOS 16.2, *) {
                RestActivityManager.shared.stopActivity()
            }
        }
        completionHandler()
    }
}

class FormMediaSchemeHandler: NSObject, WKURLSchemeHandler {
    static var notesMediaDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("NotesMedia", isDirectory: true)
        if !FileManager.default.fileExists(atPath: docs.path) {
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        }
        return docs
    }
    
    static func deleteMediaFile(urlStringOrName: String) {
        guard !urlStringOrName.isEmpty else { return }
        var cleanName = urlStringOrName
        if cleanName.hasPrefix("form-media://") {
            cleanName = String(cleanName.dropFirst("form-media://".count))
        }
        cleanName = cleanName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleanName.isEmpty else { return }
        let fileURL = notesMediaDirectory.appendingPathComponent(cleanName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "FormMedia", code: 400, userInfo: nil))
            return
        }
        
        let rawName = (url.host ?? "").isEmpty ? url.lastPathComponent : (url.host ?? "")
        let fileName = rawName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fileURL = Self.notesMediaDirectory.appendingPathComponent(fileName)
        
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Access-Control-Allow-Origin": "*"])
            if let resp = resp {
                urlSchemeTask.didReceive(resp)
            }
            urlSchemeTask.didFailWithError(NSError(domain: "FormMedia", code: 404, userInfo: [NSLocalizedDescriptionKey: "File not found"]))
            return
        }
        
        let ext = fileURL.pathExtension.lowercased()
        let mimeType: String
        switch ext {
        case "mp4", "m4v", "mov": mimeType = "video/mp4"
        case "m4a", "aac": mimeType = "audio/mp4"
        case "mp3": mimeType = "audio/mpeg"
        case "jpg", "jpeg": mimeType = "image/jpeg"
        case "png": mimeType = "image/png"
        case "webp": mimeType = "image/webp"
        default: mimeType = "application/octet-stream"
        }
        
        let totalSize = data.count
        
        // Поддержка HTTP Range для стриминга и перемотки аудио/видео без фризов
        if let rangeHeader = urlSchemeTask.request.value(forHTTPHeaderField: "Range"),
           rangeHeader.hasPrefix("bytes=") {
            let spec = String(rangeHeader.dropFirst(6))
            let parts = spec.split(separator: "-", omittingEmptySubsequences: false)
            var start = 0
            var end = totalSize - 1
            if let first = parts.first, let s = Int(first) {
                start = max(0, min(s, totalSize - 1))
            }
            if parts.count > 1, !parts[1].isEmpty, let e = Int(parts[1]) {
                end = max(start, min(e, totalSize - 1))
            }
            let subData = data.subdata(in: start..<(end + 1))
            let headers: [String: String] = [
                "Content-Type": mimeType,
                "Content-Length": "\(subData.count)",
                "Content-Range": "bytes \(start)-\(end)/\(totalSize)",
                "Accept-Ranges": "bytes",
                "Access-Control-Allow-Origin": "*"
            ]
            if let response = HTTPURLResponse(url: url, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: headers) {
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(subData)
                urlSchemeTask.didFinish()
                return
            }
        }
        
        let headers: [String: String] = [
            "Content-Type": mimeType,
            "Content-Length": "\(totalSize)",
            "Accept-Ranges": "bytes",
            "Access-Control-Allow-Origin": "*"
        ]
        if let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) {
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        }
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

struct WebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    func makeUIView(context: Context) -> WKWebView {
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationDelegate.shared
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.setURLSchemeHandler(FormMediaSchemeHandler(), forURLScheme: "form-media")
        
        let sharedDefaults = UserDefaults(suiteName: "group.com.macro.shared")
        let savedKey = sharedDefaults?.string(forKey: "nativeApiKey") ?? ""
        let savedState = sharedDefaults?.string(forKey: "nativeStateJson") ?? ""
        
        let escapedKey = savedKey
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "")
        
        let stateLiteral = savedState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "null" : savedState
        let preloadJS = """
        window.__NATIVE_API_KEY__ = "\(escapedKey)";
        window.__NATIVE_STATE__ = \(stateLiteral);
        """
        let userScript = WKUserScript(source: preloadJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)
        config.userContentController.add(context.coordinator, name: "widgetBridge")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1.0)
        webView.scrollView.backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1.0)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        
        NotificationCenter.default.addObserver(forName: Notification.Name("FormStopRestTimerExternally"), object: nil, queue: .main) { _ in
            webView.evaluateJavaScript("""
                if (typeof stopRestTimer === 'function') { stopRestTimer(); }
                if (typeof closeRestTimer === 'function') { closeRestTimer(); }
                if (typeof cancelRestTimer === 'function') { cancelRestTimer(); }
                var bar = document.getElementById('rest-timer-bar') || document.getElementById('rest-bar');
                if (bar) { bar.classList.remove('active', 'open', 'visible'); bar.style.display = 'none'; }
            """, completionHandler: nil)
        }
        
        WebViewModel.shared.webView = webView
        
        if let filePath = Bundle.main.path(forResource: "index", ofType: "html"),
           let htmlString = try? String(contentsOfFile: filePath, encoding: .utf8) {
            webView.loadHTMLString(htmlString, baseURL: URL(string: "https://macro.local"))
        }
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler, PHPickerViewControllerDelegate {
        private let pedometer = CMPedometer()
        weak var currentWebView: WKWebView?
        var pendingNoteId: String = ""
        var pendingExName: String = ""
        
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let route = WebViewModel.shared.pendingRoute {
                WebViewModel.shared.pendingRoute = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    webView.evaluateJavaScript("switchMainView('\(route)');", completionHandler: nil)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                webView.evaluateJavaScript("if (typeof checkNativeStepsOnStartup === 'function') { checkNativeStepsOnStartup(); }", completionHandler: nil)
            }
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "widgetBridge",
                  let dict = message.body as? [String: Any] else { return }
            
            let action = dict["action"] as? String ?? "syncData"
            if action == "fetchMotionSteps" {
                let wv = message.webView
                if CMPedometer.isStepCountingAvailable() {
                    let cal = Calendar.current
                    let startOfDay = cal.startOfDay(for: Date())
                    pedometer.queryPedometerData(from: startOfDay, to: Date()) { data, error in
                        guard let data = data, error == nil else { return }
                        let steps = data.numberOfSteps.intValue
                        DispatchQueue.main.async {
                            wv?.evaluateJavaScript("if (typeof onNativeStepsReceived === 'function') { onNativeStepsReceived(\(steps)); }", completionHandler: nil)
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        wv?.evaluateJavaScript("if (typeof onNativeStepsUnavailable === 'function') { onNativeStepsUnavailable(); }", completionHandler: nil)
                    }
                }
                return
            }
            if action == "testNotification" {
                let text = dict["text"] as? String ?? "Проверь остаток по калориям и белку."
                scheduleTestPush(text: text)
                return
            }
            if action == "scheduleNotifications" {
                let mode = dict["pushMode"] as? String ?? "off"
                let time1 = dict["time1"] as? String ?? "14:00"
                let time2 = dict["time2"] as? String ?? "23:00"
                let messages = dict["messages"] as? [String] ?? ["Запиши свой рацион в form."]
                scheduleDailyRandomPushes(mode: mode, time1: time1, time2: time2, messages: messages)
                return
            }
            if action == "startRestNotification" {
                let seconds = dict["seconds"] as? Double ?? 180.0
                let text = dict["text"] as? String ?? "Отдых окончен! Время подхода."
                let exName = dict["exerciseName"] as? String ?? "Подход"
                let themeCalHex = dict["themeCalHex"] as? String ?? "#D62828"
                scheduleRestNotification(seconds: seconds, text: text)
                let wv = message.webView
                RestActivityManager.shared.startActivity(seconds: seconds, exerciseName: exName, themeCalHex: themeCalHex) {
                    DispatchQueue.main.async {
                        wv?.evaluateJavaScript("if (typeof showToast === 'function') { showToast('Включите «Эфир активности» для form в Настройках iPhone', true); }", completionHandler: nil)
                    }
                }
                return
            }
            if action == "cancelRestNotification" {
                cancelRestNotification()
                RestActivityManager.shared.stopActivity()
                if let d = UserDefaults(suiteName: "group.com.macro.shared") {
                    d.set(0.0, forKey: "restTimerEndDate")
                    d.synchronize()
                    WidgetCenter.shared.reloadAllTimelines()
                }
                return
            }
            if action == "pickNoteMedia" {
                let noteId = dict["noteId"] as? String ?? "note_\(Int(Date().timeIntervalSince1970 * 1000))"
                let exName = dict["exName"] as? String ?? ""
                presentMediaPicker(noteId: noteId, exName: exName, webView: message.webView)
                return
            }
            if action == "deleteNoteMedia" {
                if let fileNames = dict["fileNames"] as? [String] {
                    for name in fileNames {
                        FormMediaSchemeHandler.deleteMediaFile(urlStringOrName: name)
                    }
                }
                return
            }
            
            guard let d = UserDefaults(suiteName: "group.com.macro.shared") else { return }
            if let apiKey = dict["apiKey"] as? String { d.set(apiKey, forKey: "nativeApiKey") }
            if let stateJson = dict["stateJson"] as? String, !stateJson.isEmpty { d.set(stateJson, forKey: "nativeStateJson") }
            if let calHex = dict["calHex"] as? String { d.set(calHex, forKey: "calHex") }
            if let pHex = dict["pHex"] as? String { d.set(pHex, forKey: "pHex") }
            if let cHex = dict["cHex"] as? String { d.set(cHex, forKey: "cHex") }
            if let fHex = dict["fHex"] as? String { d.set(fHex, forKey: "fHex") }
            
            let curCal = (dict["cal"] as? Int) ?? (dict["cal"] as? NSNumber)?.intValue ?? 0
            let targetCal = (dict["targetCal"] as? Int) ?? (dict["targetCal"] as? NSNumber)?.intValue ?? 2000
            let curP = (dict["p"] as? Int) ?? (dict["p"] as? NSNumber)?.intValue ?? 0
            let targetP = (dict["targetP"] as? Int) ?? (dict["targetP"] as? NSNumber)?.intValue ?? 140
            let curF = (dict["f"] as? Int) ?? (dict["f"] as? NSNumber)?.intValue ?? 0
            let targetF = (dict["targetF"] as? Int) ?? (dict["targetF"] as? NSNumber)?.intValue ?? 65
            let curC = (dict["c"] as? Int) ?? (dict["c"] as? NSNumber)?.intValue ?? 0
            let targetC = (dict["targetC"] as? Int) ?? (dict["targetC"] as? NSNumber)?.intValue ?? 215

            d.set(curCal, forKey: "cal")
            d.set(targetCal, forKey: "targetCal")
            d.set(curP, forKey: "p")
            d.set(targetP, forKey: "targetP")
            d.set(curF, forKey: "f")
            d.set(targetF, forKey: "targetF")
            d.set(curC, forKey: "c")
            d.set(targetC, forKey: "targetC")
            
            // Данные тренировки, календаря и стека для двух виджетов
            d.set(dict["splitTitle"] as? String ?? "День 1 · Жим", forKey: "splitTitle")
            d.set(dict["isRestDay"] as? Bool ?? false, forKey: "isRestDay")
            let setsDone = (dict["setsDone"] as? Int) ?? (dict["setsDone"] as? NSNumber)?.intValue ?? 0
            let setsTarget = (dict["setsTarget"] as? Int) ?? (dict["setsTarget"] as? NSNumber)?.intValue ?? 60
            d.set(setsDone, forKey: "setsDone")
            d.set(setsTarget, forKey: "setsTarget")
            d.set(dict["weekBadges"] as? String ?? "Д1,Д2,ОТД,Д3,ОТД,Д4,ОТД", forKey: "weekBadges")
            d.set(dict["currentWeight"] as? String ?? "", forKey: "currentWeight")
            d.set(dict["stackDone"] as? Int ?? 0, forKey: "stackDone")
            d.set(dict["stackTotal"] as? Int ?? 4, forKey: "stackTotal")
            
            if let restEnd = dict["restTimerEndDate"] as? Double {
                d.set(restEnd, forKey: "restTimerEndDate")
            }
            
            d.synchronize()
            WidgetCenter.shared.reloadAllTimelines()
        }
        
        private func scheduleTestPush(text: String) {
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                guard granted else { return }
                let content = UNMutableNotificationContent()
                content.title = "form // КБЖУ"
                content.body = text
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                center.add(UNNotificationRequest(identifier: "form_test_\(UUID().uuidString)", content: content, trigger: trigger))
            }
        }
        
        private func scheduleRestNotification(seconds: Double, text: String) {
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: ["form_rest_timer"])
            guard seconds > 0 else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                guard granted else { return }
                let content = UNMutableNotificationContent()
                content.title = "Отдых окончен!"
                content.body = text
                content.sound = .default
                if #available(iOS 15.0, *) {
                    content.interruptionLevel = .timeSensitive
                }
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
                center.add(UNNotificationRequest(identifier: "form_rest_timer", content: content, trigger: trigger))
            }
        }
        
        private func cancelRestNotification() {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["form_rest_timer"])
        }
        
        private func scheduleDailyRandomPushes(mode: String, time1: String, time2: String, messages: [String]) {
            let center = UNUserNotificationCenter.current()
            center.removeAllPendingNotificationRequests()
            guard mode != "off", !messages.isEmpty else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                guard granted else { return }
                let parts1 = time1.split(separator: ":"); let h1 = parts1.count == 2 ? (Int(parts1[0]) ?? 14) : 14; let m1 = parts1.count == 2 ? (Int(parts1[1]) ?? 0) : 0
                let parts2 = time2.split(separator: ":"); let h2 = parts2.count == 2 ? (Int(parts2[0]) ?? 23) : 23; let m2 = parts2.count == 2 ? (Int(parts2[1]) ?? 0) : 0
                var slots: [(Int, Int)] = []
                if mode == "2x" { slots = [(h1, m1), (h2, m2)] }
                else if mode == "mid" { slots = [(h1, m1)] }
                else if mode == "eve" { slots = [(h2, m2)] }
                
                let cal = Calendar.current; let now = Date()
                for dayOffset in 0..<14 {
                    guard let targetDate = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
                    for (idx, slot) in slots.enumerated() {
                        var comps = cal.dateComponents([.year, .month, .day], from: targetDate)
                        comps.hour = slot.0; comps.minute = slot.1
                        if let fireDate = cal.date(from: comps), fireDate > now {
                            let content = UNMutableNotificationContent()
                            content.title = idx == 0 && slots.count > 1 ? "form // Дневной чек-ин" : "form // Итоги рациона"
                            content.body = messages.randomElement() ?? "Запиши свой рацион."
                            content.sound = .default
                            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                            center.add(UNNotificationRequest(identifier: "form_daily_\(dayOffset)_\(idx)", content: content, trigger: trigger))
                        }
                    }
                }
            }
        }
        
        static func topViewController(base: UIViewController? = nil) -> UIViewController? {
            let root: UIViewController?
            if let base = base {
                root = base
            } else {
                root = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }
                    .first { $0.isKeyWindow }?
                    .rootViewController
            }
            if let nav = root as? UINavigationController {
                return topViewController(base: nav.visibleViewController)
            }
            if let tab = root as? UITabBarController {
                return topViewController(base: tab.selectedViewController)
            }
            if let presented = root?.presentedViewController {
                return topViewController(base: presented)
            }
            return root
        }

        func presentMediaPicker(noteId: String, exName: String, webView: WKWebView?) {
            self.currentWebView = webView
            self.pendingNoteId = noteId
            self.pendingExName = exName
            var config = PHPickerConfiguration()
            config.selectionLimit = 1
            config.filter = .any(of: [.images, .videos])
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            DispatchQueue.main.async {
                Self.topViewController()?.present(picker, animated: true)
            }
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else {
                DispatchQueue.main.async {
                    self.currentWebView?.evaluateJavaScript("if (typeof window.onNoteMediaPicked === 'function') { window.onNoteMediaPicked({ cancelled: true }); }", completionHandler: nil)
                }
                return
            }

            let noteId = self.pendingNoteId
            let exName = self.pendingExName
            let uuid = UUID().uuidString
            let mediaDir = FormMediaSchemeHandler.notesMediaDirectory
            let isVideo = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)

            DispatchQueue.main.async {
                self.currentWebView?.evaluateJavaScript("if (typeof window.onNoteMediaLoading === 'function') { window.onNoteMediaLoading({ type: '\(isVideo ? "video" : "photo")', exName: '\(exName)' }); }", completionHandler: nil)
            }

            if isVideo {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] tempUrl, error in
                    guard let tempUrl = tempUrl, error == nil else {
                        DispatchQueue.main.async {
                            self?.currentWebView?.evaluateJavaScript("if (typeof window.onNoteMediaPicked === 'function') { window.onNoteMediaPicked({ error: 'Не удалось загрузить видео' }); }", completionHandler: nil)
                        }
                        return
                    }

                    let videoDst = mediaDir.appendingPathComponent("video_\(uuid).mp4")
                    let audioDst = mediaDir.appendingPathComponent("audio_\(uuid).m4a")
                    let thumbDst = mediaDir.appendingPathComponent("thumb_\(uuid).jpg")

                    try? FileManager.default.removeItem(at: videoDst)
                    try? FileManager.default.copyItem(at: tempUrl, to: videoDst)

                    let asset = AVURLAsset(url: videoDst)
                    let duration = CMTimeGetSeconds(asset.duration)

                    let gen = AVAssetImageGenerator(asset: asset)
                    gen.appliesPreferredTrackTransform = true
                    let time = CMTime(seconds: 0.1, preferredTimescale: 600)
                    if let imageRef = try? gen.copyCGImage(at: time, actualTime: nil) {
                        let thumbImg = UIImage(cgImage: imageRef)
                        if let thumbData = thumbImg.jpegData(compressionQuality: 0.75) {
                            try? thumbData.write(to: thumbDst)
                        }
                    }

                    // Мгновенный вызов JS: превью и возможность сразу сохранить заметку без задержки!
                    DispatchQueue.main.async {
                        let thumbParam = FileManager.default.fileExists(atPath: thumbDst.path) ? "'form-media://thumb_\(uuid).jpg'" : "null"
                        let durValue = duration.isNaN ? 0.0 : duration
                        let js = """
                        if (typeof window.onNoteMediaPicked === 'function') {
                            window.onNoteMediaPicked({
                                success: true,
                                noteId: '\(noteId)',
                                exName: '\(exName)',
                                type: 'video',
                                url: 'form-media://video_\(uuid).mp4',
                                audioUrl: null,
                                thumbUrl: \(thumbParam),
                                duration: \(durValue)
                            });
                        }
                        """
                        self?.currentWebView?.evaluateJavaScript(js, completionHandler: nil)
                    }

                    // Фоновое извлечение аудиодорожки .m4a
                    if let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) {
                        try? FileManager.default.removeItem(at: audioDst)
                        exportSession.outputURL = audioDst
                        exportSession.outputFileType = .m4a
                        exportSession.exportAsynchronously { [weak self] in
                            if exportSession.status == .completed {
                                DispatchQueue.main.async {
                                    let updateJs = """
                                    if (typeof window.onNoteAudioExtracted === 'function') {
                                        window.onNoteAudioExtracted({
                                            noteId: '\(noteId)',
                                            videoUrl: 'form-media://video_\(uuid).mp4',
                                            audioUrl: 'form-media://audio_\(uuid).m4a'
                                        });
                                    }
                                    """
                                    self?.currentWebView?.evaluateJavaScript(updateJs, completionHandler: nil)
                                }
                            }
                        }
                    }
                }
            } else if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                    guard let image = object as? UIImage, error == nil else {
                        DispatchQueue.main.async {
                            self?.currentWebView?.evaluateJavaScript("if (typeof window.onNoteMediaPicked === 'function') { window.onNoteMediaPicked({ error: 'Не удалось загрузить фото' }); }", completionHandler: nil)
                        }
                        return
                    }

                    let maxSide: CGFloat = 2048
                    var finalImg = image
                    if max(image.size.width, image.size.height) > maxSide {
                        let ratio = maxSide / max(image.size.width, image.size.height)
                        let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                        image.draw(in: CGRect(origin: .zero, size: newSize))
                        if let scaled = UIGraphicsGetImageFromCurrentImageContext() {
                            finalImg = scaled
                        }
                        UIGraphicsEndImageContext()
                    }

                    let photoDst = mediaDir.appendingPathComponent("photo_\(uuid).jpg")
                    if let jpegData = finalImg.jpegData(compressionQuality: 0.85) {
                        try? jpegData.write(to: photoDst)
                    }

                    DispatchQueue.main.async {
                        let js = """
                        if (typeof window.onNoteMediaPicked === 'function') {
                            window.onNoteMediaPicked({
                                success: true,
                                noteId: '\(noteId)',
                                exName: '\(exName)',
                                type: 'photo',
                                url: 'form-media://photo_\(uuid).jpg',
                                thumbUrl: 'form-media://photo_\(uuid).jpg'
                            });
                        }
                        """
                        self?.currentWebView?.evaluateJavaScript(js, completionHandler: nil)
                    }
                }
            }
        }
    }
}

struct ContentView: View {
    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.03, blue: 0.04).ignoresSafeArea()
            WebView().ignoresSafeArea(.container, edges: .vertical)
        }
        .preferredColorScheme(.dark)
        .onOpenURL { url in
            let str = url.absoluteString.lowercased()
            if str.contains("split") {
                WebViewModel.shared.navigate(to: "split")
            } else if str.contains("diet") {
                WebViewModel.shared.navigate(to: "diet")
            }
        }
    }
}
