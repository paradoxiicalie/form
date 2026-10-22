import SwiftUI
import WebKit
import WidgetKit
import UserNotifications

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.identifier == "form_rest_timer" {
            // Когда пользователь находится внутри приложения, интерфейс сам выводит тост и играет зальный сигнал
            completionHandler([])
        } else {
            completionHandler([.banner, .sound, .list])
        }
    }
}

struct WebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    func makeUIView(context: Context) -> WKWebView {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
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
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1.0)
        webView.scrollView.backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1.0)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        
        if let filePath = Bundle.main.path(forResource: "index", ofType: "html"),
           let htmlString = try? String(contentsOfFile: filePath, encoding: .utf8) {
            webView.loadHTMLString(htmlString, baseURL: URL(string: "https://macro.local"))
        }
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    class Coordinator: NSObject, WKUIDelegate, WKScriptMessageHandler {
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "widgetBridge",
                  let dict = message.body as? [String: Any] else { return }
            
            let action = dict["action"] as? String ?? "syncData"
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
                scheduleRestNotification(seconds: seconds, text: text)
                return
            }
            if action == "cancelRestNotification" {
                cancelRestNotification()
                return
            }
            
            guard let d = UserDefaults(suiteName: "group.com.macro.shared") else { return }
            if let apiKey = dict["apiKey"] as? String { d.set(apiKey, forKey: "nativeApiKey") }
            if let stateJson = dict["stateJson"] as? String, !stateJson.isEmpty { d.set(stateJson, forKey: "nativeStateJson") }
            if let calHex = dict["calHex"] as? String { d.set(calHex, forKey: "calHex") }
            if let pHex = dict["pHex"] as? String { d.set(pHex, forKey: "pHex") }
            if let cHex = dict["cHex"] as? String { d.set(cHex, forKey: "cHex") }
            if let fHex = dict["fHex"] as? String { d.set(fHex, forKey: "fHex") }
            
            d.set(dict["cal"] as? Int ?? 0, forKey: "cal")
            d.set(dict["targetCal"] as? Int ?? 2979, forKey: "targetCal")
            d.set(dict["p"] as? Int ?? 0, forKey: "p")
            d.set(dict["targetP"] as? Int ?? 130, forKey: "targetP")
            d.set(dict["f"] as? Int ?? 0, forKey: "f")
            d.set(dict["targetF"] as? Int ?? 67, forKey: "targetF")
            d.set(dict["c"] as? Int ?? 0, forKey: "c")
            d.set(dict["targetC"] as? Int ?? 464, forKey: "targetC")
            
            // Данные тренировки, календаря и стека для двух виджетов
            d.set(dict["splitTitle"] as? String ?? "День 1 · Жим", forKey: "splitTitle")
            d.set(dict["isRestDay"] as? Bool ?? false, forKey: "isRestDay")
            d.set(dict["setsDone"] as? Int ?? 0, forKey: "setsDone")
            d.set(dict["setsTarget"] as? Int ?? 52, forKey: "setsTarget")
            d.set(dict["weekBadges"] as? String ?? "Д1,Д2,ОТД,Д3,ОТД,Д4,ОТД", forKey: "weekBadges")
            d.set(dict["currentWeight"] as? String ?? "70", forKey: "currentWeight")
            d.set(dict["stackDone"] as? Int ?? 0, forKey: "stackDone")
            d.set(dict["stackTotal"] as? Int ?? 4, forKey: "stackTotal")
            
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
                content.title = "⏱ Отдых окончен!"
                content.body = text
                content.sound = .default
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
    }
}

struct ContentView: View {
    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.03, blue: 0.04).ignoresSafeArea()
            WebView().ignoresSafeArea(.container, edges: .vertical)
        }
        .preferredColorScheme(.dark)
    }
}

