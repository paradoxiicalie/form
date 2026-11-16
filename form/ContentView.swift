import SwiftUI
import Combine
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

final class WebViewModel: ObservableObject {
    static let shared = WebViewModel()
    weak var webView: WKWebView?
    var pendingRoute: String?
    
    @Published var currentView: String = "diet"
    @Published var isModalOpen: Bool = false
    @Published var accentHex: String = {
        let d = UserDefaults(suiteName: "group.com.macro.shared")
        return d?.string(forKey: "calHex") ?? "#D62828"
    }()
    
    func navigate(to route: String) {
        if currentView != route {
            currentView = route
        }
        if let wv = webView {
            wv.evaluateJavaScript("switchMainView('\(route)');", completionHandler: nil)
        } else {
            pendingRoute = route
        }
    }
    
    func handleTopRightAction() {
        if let wv = webView {
            wv.evaluateJavaScript("if (typeof handleTopRightAction === 'function') { handleTopRightAction(); }", completionHandler: nil)
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 214, 40, 40)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
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

class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasDetected = false
    private var lastDetectedCode: String?
    private var detectionConfirmCount = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasDetected = false
        lastDetectedCode = nil
        detectionConfirmCount = 0
        if let session = captureSession, !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let session = captureSession, session.isRunning {
            session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
              session.canAddInput(videoInput) else {
            return
        }

        session.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else { return }
        session.addOutput(metadataOutput)

        metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        metadataOutput.metadataObjectTypes = [.ean13, .upce]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.layer.bounds
        view.layer.addSublayer(preview)
        self.previewLayer = preview
        self.captureSession = session

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    private func setupUI() {
        let reticle = UIView()
        reticle.translatesAutoresizingMaskIntoConstraints = false
        reticle.layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        reticle.layer.borderWidth = 2
        reticle.layer.cornerRadius = 16
        reticle.backgroundColor = .clear
        view.addSubview(reticle)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "FORM // СКАНЕР ШТРИХКОДОВ"
        label.textColor = .white
        label.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        label.textAlignment = .center
        view.addSubview(label)

        let hint = UILabel()
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.text = "Наведите рамку на штрихкод товара"
        hint.textColor = UIColor(white: 0.65, alpha: 1.0)
        hint.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        hint.textAlignment = .center
        view.addSubview(hint)

        let closeBtn = UIButton(type: .system)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.setTitle("✕", for: .normal)
        closeBtn.setTitleColor(.white, for: .normal)
        closeBtn.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        closeBtn.backgroundColor = UIColor(white: 0.15, alpha: 0.85)
        closeBtn.layer.cornerRadius = 20
        closeBtn.addTarget(self, action: #selector(didTapClose), for: .touchUpInside)
        view.addSubview(closeBtn)

        NSLayoutConstraint.activate([
            closeBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeBtn.widthAnchor.constraint(equalToConstant: 40),
            closeBtn.heightAnchor.constraint(equalToConstant: 40),

            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 26),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            reticle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            reticle.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            reticle.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.78),
            reticle.heightAnchor.constraint(equalToConstant: 180),

            hint.topAnchor.constraint(equalTo: reticle.bottomAnchor, constant: 20),
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    @objc private func didTapClose() {
        dismiss(animated: true)
    }

    private func isValidEANOrUPC(_ code: String, type: AVMetadataObject.ObjectType) -> Bool {
        let digits = code.filter { $0.isNumber }
        if type == .ean13 {
            guard digits.count == 13 else { return false }
            let nums = digits.compactMap { Int(String($0)) }
            guard nums.count == 13 else { return false }
            var sum = 0
            for i in 0..<12 {
                sum += nums[i] * (i % 2 == 0 ? 1 : 3)
            }
            let check = (10 - (sum % 10)) % 10
            return check == nums[12]
        }
        if type == .upce {
            // UPC-E на iOS состоит из 8 цифр и начинается строго с 0 или 1
            return digits.count == 8 && (digits.first == "0" || digits.first == "1")
        }
        return false
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasDetected,
              let metadataObj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringVal = metadataObj.stringValue,
              isValidEANOrUPC(stringVal, type: metadataObj.type) else {
            return
        }
        let cleanCode = stringVal.filter { $0.isNumber }
        if lastDetectedCode == cleanCode {
            detectionConfirmCount += 1
        } else {
            lastDetectedCode = cleanCode
            detectionConfirmCount = 1
        }
        guard detectionConfirmCount >= 2 else { return }

        hasDetected = true
        captureSession?.stopRunning()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss(animated: true) { [weak self] in
            self?.onCodeScanned?(cleanCode)
        }
    }
}

class FormMediaSchemeHandler: NSObject, WKURLSchemeHandler {
    private var activeTasks = Set<ObjectIdentifier>()
    private let tasksLock = NSLock()
    
    private func registerTask(_ task: WKURLSchemeTask) {
        tasksLock.lock()
        activeTasks.insert(ObjectIdentifier(task))
        tasksLock.unlock()
    }
    
    private func unregisterTask(_ task: WKURLSchemeTask) {
        tasksLock.lock()
        activeTasks.remove(ObjectIdentifier(task))
        tasksLock.unlock()
    }
    
    private func isTaskActive(_ task: WKURLSchemeTask) -> Bool {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        return activeTasks.contains(ObjectIdentifier(task))
    }

    static var notesMediaDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("NotesMedia", isDirectory: true)
        if !FileManager.default.fileExists(atPath: docs.path) {
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        }
        return docs
    }
    
    static var diskBackupURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("form_state_backup.json")
    }
    
    static func saveDiskBackup(jsonString: String) {
        guard !jsonString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = jsonString.data(using: .utf8) else { return }
        try? data.write(to: diskBackupURL, options: .atomic)
    }
    
    static func loadDiskBackup() -> String? {
        guard FileManager.default.fileExists(atPath: diskBackupURL.path),
              let data = try? Data(contentsOf: diskBackupURL),
              let str = String(data: data, encoding: .utf8),
              !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return str
    }
    
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func extractMediaFileName(from raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let qIdx = trimmed.firstIndex(of: "?") {
            trimmed = String(trimmed[..<qIdx])
        }
        if trimmed.hasPrefix("form-media://") {
            trimmed = String(trimmed.dropFirst("form-media://".count))
        } else if trimmed.hasPrefix("file://") {
            trimmed = String(trimmed.dropFirst("file://".count))
        }
        let comps = trimmed.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        return comps.last ?? ""
    }

    static func extractMediaFileName(from url: URL) -> String {
        let last = url.lastPathComponent.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !last.isEmpty && last != "/" {
            return last
        }
        return extractMediaFileName(from: url.absoluteString)
    }

    static func resolveMediaFileURL(rawUrlOrName: String) -> URL? {
        let fileName = extractMediaFileName(from: rawUrlOrName)
        guard !fileName.isEmpty else { return nil }
        let primary = notesMediaDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: primary.path) {
            return primary
        }
        let fallback = documentsDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }
        return nil
    }

    static func deleteMediaFile(urlStringOrName: String) {
        let fileName = extractMediaFileName(from: urlStringOrName)
        guard !fileName.isEmpty else { return }
        try? FileManager.default.removeItem(at: notesMediaDirectory.appendingPathComponent(fileName))
        try? FileManager.default.removeItem(at: documentsDirectory.appendingPathComponent(fileName))
    }

    static func cleanupOrphanedMediaFiles(activeFileNames: Set<String>) {
        // Не выполняем очистку, если передан пустой набор без явного подтверждения
        let normalized = Set(activeFileNames.map { extractMediaFileName(from: $0) }.filter { !$0.isEmpty })
        let dir = notesMediaDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for file in files {
            guard !file.hasPrefix(".") else { continue }
            if !normalized.contains(file) {
                let fileURL = dir.appendingPathComponent(file)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        registerTask(urlSchemeTask)
        
        guard let url = urlSchemeTask.request.url else {
            if isTaskActive(urlSchemeTask) {
                urlSchemeTask.didFailWithError(NSError(domain: "FormMedia", code: 400, userInfo: nil))
            }
            unregisterTask(urlSchemeTask)
            return
        }
        
        let fileName = Self.extractMediaFileName(from: url)
        guard let fileURL = Self.resolveMediaFileURL(rawUrlOrName: fileName),
              let attr = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attr[.size] as? UInt64, fileSize > 0 else {
            if isTaskActive(urlSchemeTask) {
                let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Access-Control-Allow-Origin": "*"])
                if let resp = resp {
                    urlSchemeTask.didReceive(resp)
                }
                urlSchemeTask.didFailWithError(NSError(domain: "FormMedia", code: 404, userInfo: [NSLocalizedDescriptionKey: "File not found"]))
            }
            unregisterTask(urlSchemeTask)
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
        
        let totalSize = Int(fileSize)
        
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            if isTaskActive(urlSchemeTask) {
                urlSchemeTask.didFailWithError(NSError(domain: "FormMedia", code: 500, userInfo: nil))
            }
            unregisterTask(urlSchemeTask)
            return
        }
        defer { try? fileHandle.close() }
        
        // Поддержка HTTP Range через FileHandle: читаем ровно запрошенный чанк без выгрузки гигабайтов в RAM
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
            // Ограничиваем максимальный размер чанка до 1 МБ для плавной подгрузки и моментальной паузы без лагов звука
            let maxChunk = 1024 * 1024 // 1 MB
            if (end - start + 1) > maxChunk {
                end = start + maxChunk - 1
            }
            let lengthToRead = end - start + 1
            try? fileHandle.seek(toOffset: UInt64(start))
            let subData = fileHandle.readData(ofLength: lengthToRead)
            
            let headers: [String: String] = [
                "Content-Type": mimeType,
                "Content-Length": "\(subData.count)",
                "Content-Range": "bytes \(start)-\(end)/\(totalSize)",
                "Accept-Ranges": "bytes",
                "Access-Control-Allow-Origin": "*"
            ]
            if isTaskActive(urlSchemeTask),
               let response = HTTPURLResponse(url: url, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: headers) {
                urlSchemeTask.didReceive(response)
                if isTaskActive(urlSchemeTask) {
                    urlSchemeTask.didReceive(subData)
                }
                if isTaskActive(urlSchemeTask) {
                    urlSchemeTask.didFinish()
                }
                unregisterTask(urlSchemeTask)
                return
            }
        }
        
        let data = fileHandle.readDataToEndOfFile()
        let headers: [String: String] = [
            "Content-Type": mimeType,
            "Content-Length": "\(totalSize)",
            "Accept-Ranges": "bytes",
            "Access-Control-Allow-Origin": "*"
        ]
        if isTaskActive(urlSchemeTask),
           let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) {
            urlSchemeTask.didReceive(response)
            if isTaskActive(urlSchemeTask) {
                urlSchemeTask.didReceive(data)
            }
            if isTaskActive(urlSchemeTask) {
                urlSchemeTask.didFinish()
            }
        }
        unregisterTask(urlSchemeTask)
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        unregisterTask(urlSchemeTask)
    }
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
        var savedState = sharedDefaults?.string(forKey: "nativeStateJson") ?? sharedDefaults?.string(forKey: "formNativeBackupJSON") ?? ""
        if savedState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            savedState = FormMediaSchemeHandler.loadDiskBackup() ?? ""
        }
        
        let escapedKey = savedKey
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "")
        
        let trimmedState = savedState.trimmingCharacters(in: .whitespacesAndNewlines)
        let stateLiteral: String
        if !trimmedState.isEmpty,
           let data = trimmedState.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            stateLiteral = trimmedState
        } else {
            stateLiteral = "null"
        }

        let preloadJS = """
        window.__NATIVE_API_KEY__ = "\(escapedKey)";
        window.__NATIVE_STATE__ = \(stateLiteral);
        """
        let userScript = WKUserScript(source: preloadJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)
        config.userContentController.add(context.coordinator, name: "widgetBridge")
        config.userContentController.add(context.coordinator, name: "iosBridge")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1.0)
        webView.scrollView.backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1.0)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        
        context.coordinator.setupNotificationObservers(webView: webView)
        
        WebViewModel.shared.webView = webView
        context.coordinator.currentWebView = webView
        
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
        private var notificationTokens: [NSObjectProtocol] = []
        
        override init() {
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWillEnterForeground),
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
        }
        
        func setupNotificationObservers(webView: WKWebView) {
            removeNotificationObservers()
            
            let t1 = NotificationCenter.default.addObserver(forName: Notification.Name("FormStopRestTimerExternally"), object: nil, queue: .main) { [weak webView] _ in
                webView?.evaluateJavaScript("""
                    if (typeof stopRestTimer === 'function') { stopRestTimer(); }
                    if (typeof closeRestTimer === 'function') { closeRestTimer(); }
                    if (typeof cancelRestTimer === 'function') { cancelRestTimer(); }
                    var bar = document.getElementById('restTimerFloatingBar');
                    if (bar) { bar.classList.add('hidden'); }
                    if (typeof window.onRestTimerStopped === 'function') { window.onRestTimerStopped(); }
                """, completionHandler: nil)
            }
            
            let t2 = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak webView] _ in
                if let d = UserDefaults(suiteName: "group.com.macro.shared"),
                   d.bool(forKey: "restTimerStoppedExternally") {
                    d.set(false, forKey: "restTimerStoppedExternally")
                    d.synchronize()
                    webView?.evaluateJavaScript("""
                        if (typeof stopRestTimer === 'function') { stopRestTimer(); }
                        if (typeof closeRestTimer === 'function') { closeRestTimer(); }
                        if (typeof cancelRestTimer === 'function') { cancelRestTimer(); }
                        var bar = document.getElementById('restTimerFloatingBar');
                        if (bar) { bar.classList.add('hidden'); }
                        if (typeof window.onRestTimerStopped === 'function') { window.onRestTimerStopped(); }
                    """, completionHandler: nil)
                }
            }
            notificationTokens = [t1, t2]
        }
        
        func removeNotificationObservers() {
            for token in notificationTokens {
                NotificationCenter.default.removeObserver(token)
            }
            notificationTokens.removeAll()
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
            removeNotificationObservers()
        }
        
        @objc private func handleWillEnterForeground() {
            syncStepsSilently(webView: currentWebView ?? WebViewModel.shared.webView)
        }
        
        func syncStepsSilently(webView: WKWebView?) {
            guard let wv = webView ?? currentWebView ?? WebViewModel.shared.webView else { return }
            if CMPedometer.isStepCountingAvailable() {
                let cal = Calendar.current
                let startOfDay = cal.startOfDay(for: Date())
                pedometer.queryPedometerData(from: startOfDay, to: Date()) { [weak wv] data, error in
                    guard let data = data, error == nil else { return }
                    let steps = data.numberOfSteps.intValue
                    DispatchQueue.main.async {
                        wv?.evaluateJavaScript("if (typeof onNativeStepsReceived === 'function') { onNativeStepsReceived(\(steps), true); }", completionHandler: nil)
                    }
                }
            }
        }
        
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.currentWebView = webView
            if let route = WebViewModel.shared.pendingRoute {
                WebViewModel.shared.pendingRoute = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    webView.evaluateJavaScript("switchMainView('\(route)');", completionHandler: nil)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.syncStepsSilently(webView: webView)
            }
            // Восстанавливаем базу из нативного бэкапа без задержек, если localStorage пуст
            if let d = UserDefaults(suiteName: "group.com.macro.shared"),
               let json = d.string(forKey: "formNativeBackupJSON") ?? FormMediaSchemeHandler.loadDiskBackup(), !json.isEmpty {
                let escaped = json
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                webView.evaluateJavaScript("""
                    (function(){
                        var KEYS = ['macro_minimal_ios_v9','macro_minimal_ios_v8','macro_minimal_ios_v7'];
                        var hasData = KEYS.some(function(k){ var v = localStorage.getItem(k); return v && v.length > 50; });
                        if (!hasData) {
                            try {
                                var json = `\(escaped)`;
                                localStorage.setItem(KEYS[0], json);
                                if (typeof loadState === 'function') { loadState(); }
                                if (typeof renderAll === 'function') { renderAll(); }
                            } catch(e) {}
                        }
                    })();
                """, completionHandler: nil)
            }
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "widgetBridge" || message.name == "iosBridge",
                  let dict = message.body as? [String: Any] else { return }
            
            let action = dict["action"] as? String ?? "syncData"
            if action == "mainViewChanged" {
                if let view = dict["view"] as? String {
                    DispatchQueue.main.async {
                        if WebViewModel.shared.currentView != view {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                WebViewModel.shared.currentView = view
                            }
                        }
                    }
                }
                return
            }
            if action == "modalVisibilityChanged" {
                let isOpen = (dict["isOpen"] as? Bool) ?? (dict["open"] as? Bool) ?? false
                DispatchQueue.main.async {
                    if WebViewModel.shared.isModalOpen != isOpen {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            WebViewModel.shared.isModalOpen = isOpen
                        }
                    }
                }
                return
            }
            if action == "themeAccentUpdated" {
                if let hex = dict["calHex"] as? String ?? dict["hex"] as? String, !hex.isEmpty {
                    DispatchQueue.main.async {
                        if WebViewModel.shared.accentHex != hex {
                            WebViewModel.shared.accentHex = hex
                        }
                    }
                }
                return
            }
            if action == "fetchMotionSteps" {
                let wv = message.webView
                let isSilent = dict["silent"] as? Bool ?? false
                if CMPedometer.isStepCountingAvailable() {
                    let cal = Calendar.current
                    let startOfDay = cal.startOfDay(for: Date())
                    pedometer.queryPedometerData(from: startOfDay, to: Date()) { data, error in
                        guard let data = data, error == nil else { return }
                        let steps = data.numberOfSteps.intValue
                        DispatchQueue.main.async {
                            wv?.evaluateJavaScript("if (typeof onNativeStepsReceived === 'function') { onNativeStepsReceived(\(steps), \(isSilent)); }", completionHandler: nil)
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
            if action == "scanBarcodeNative" {
                presentBarcodeScanner(webView: message.webView)
                return
            }
            if action == "nativeFetchGemini" {
                executeNativeGeminiFetch(dict: dict, webView: message.webView)
                return
            }
            
            if action == "backupStateToDisk" {
                let jsonString = (dict["json"] as? String) ?? (dict["data"] as? String) ?? (dict["stateJson"] as? String) ?? ""
                if !jsonString.isEmpty {
                    FormMediaSchemeHandler.saveDiskBackup(jsonString: jsonString)
                    if let d = UserDefaults(suiteName: "group.com.macro.shared") {
                        d.set(jsonString, forKey: "formNativeBackupJSON")
                        d.set(jsonString, forKey: "nativeStateJson")
                        d.synchronize()
                    }
                }
                return
            }
            if action == "cleanupOrphanedMedia" {
                let confirmed = dict["confirmed"] as? Bool ?? false
                if let activeList = dict["activeMediaFiles"] as? [String],
                   (confirmed || !activeList.isEmpty) {
                    let cleanSet = Set(activeList.map { FormMediaSchemeHandler.extractMediaFileName(from: $0) }.filter { !$0.isEmpty })
                    FormMediaSchemeHandler.cleanupOrphanedMediaFiles(activeFileNames: cleanSet)
                }
                return
            }
            if action == "haptic" {
                let style = dict["style"] as? String ?? "light"
                DispatchQueue.main.async {
                    switch style {
                    case "light":
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    case "medium":
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    case "heavy":
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    case "selection":
                        UISelectionFeedbackGenerator().selectionChanged()
                    case "success":
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    case "warning":
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    case "error":
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    default:
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                return
            }
            if action == "syncFullBackup" {
                if let jsonString = dict["data"] as? String, !jsonString.isEmpty {
                    FormMediaSchemeHandler.saveDiskBackup(jsonString: jsonString)
                    if let d = UserDefaults(suiteName: "group.com.macro.shared") {
                        d.set(jsonString, forKey: "formNativeBackupJSON")
                        d.synchronize()
                    }
                }
                return
            }
            guard let d = UserDefaults(suiteName: "group.com.macro.shared") else { return }
            if let apiKey = dict["apiKey"] as? String { d.set(apiKey, forKey: "nativeApiKey") }
            if let stateJson = dict["stateJson"] as? String, !stateJson.isEmpty {
                d.set(stateJson, forKey: "nativeStateJson")
                d.set(stateJson, forKey: "formNativeBackupJSON")
                d.synchronize()
            }
            if let calHex = dict["calHex"] as? String {
                d.set(calHex, forKey: "calHex")
                DispatchQueue.main.async {
                    if WebViewModel.shared.accentHex != calHex {
                        WebViewModel.shared.accentHex = calHex
                    }
                }
            }
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
            center.getPendingNotificationRequests { requests in
                let dailyIds = requests.map(\.identifier).filter { $0.hasPrefix("form_daily_") }
                if !dailyIds.isEmpty {
                    center.removePendingNotificationRequests(withIdentifiers: dailyIds)
                }
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

        func presentBarcodeScanner(webView: WKWebView?) {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                guard granted else {
                    DispatchQueue.main.async {
                        webView?.evaluateJavaScript("if (typeof showToast === 'function') { showToast('Разрешите доступ к камере в Настройках iPhone', true); }", completionHandler: nil)
                    }
                    return
                }
                DispatchQueue.main.async {
                    let scanner = BarcodeScannerViewController()
                    scanner.modalPresentationStyle = .fullScreen
                    scanner.onCodeScanned = { code in
                        let cleanCode = code.replacingOccurrences(of: "'", with: "")
                        webView?.evaluateJavaScript("if (typeof window.onNativeBarcodeScanned === 'function') { window.onNativeBarcodeScanned('\(cleanCode)'); }", completionHandler: nil)
                    }
                    Self.topViewController()?.present(scanner, animated: true)
                }
            }
        }

        func executeNativeGeminiFetch(dict: [String: Any], webView: WKWebView?) {
            guard let reqId = dict["reqId"] as? String,
                  let urlString = dict["url"] as? String,
                  let url = URL(string: urlString) else { return }

            let method = dict["method"] as? String ?? "POST"
            let bodyString = dict["body"] as? String
            let headers = dict["headers"] as? [String: String] ?? [:]

            var request = URLRequest(url: url, timeoutInterval: 25.0)
            request.httpMethod = method
            for (k, v) in headers {
                request.setValue(v, forHTTPHeaderField: k)
            }
            if let bodyString = bodyString {
                request.httpBody = bodyString.data(using: .utf8)
            }

            URLSession.shared.dataTask(with: request) { data, response, error in
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? (error != nil ? 500 : 200)
                let respDataString: String
                if let data = data, let str = String(data: data, encoding: .utf8) {
                    respDataString = str
                } else {
                    respDataString = "{}"
                }
                let errString = error?.localizedDescription ?? ""

                DispatchQueue.main.async {
                    let escapedResp = respDataString
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "`", with: "\\`")
                    let escapedErr = errString.replacingOccurrences(of: "'", with: "\\'")
                    let js = """
                    if (typeof window.onNativeFetchGeminiResult === 'function') {
                        window.onNativeFetchGeminiResult('\(reqId)', \(statusCode), `\(escapedResp)`, \(errString.isEmpty ? "null" : "'\(escapedErr)'"));
                    }
                    """
                    webView?.evaluateJavaScript(js, completionHandler: nil)
                }
            }.resume()
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

                    let rawTemp = mediaDir.appendingPathComponent("raw_\(uuid).mov")
                    let videoDst = mediaDir.appendingPathComponent("video_\(uuid).mp4")
                    let audioDst = mediaDir.appendingPathComponent("audio_\(uuid).m4a")
                    let thumbDst = mediaDir.appendingPathComponent("thumb_\(uuid).jpg")

                    try? FileManager.default.removeItem(at: rawTemp)
                    try? FileManager.default.copyItem(at: tempUrl, to: rawTemp)

                    let asset = AVURLAsset(url: rawTemp)
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

                    // Аппаратное транскодирование в оптимизированный 720p H.264 с fast-start moov атомом
                    try? FileManager.default.removeItem(at: videoDst)
                    if let exportVideo = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) {
                        exportVideo.outputURL = videoDst
                        exportVideo.outputFileType = .mp4
                        exportVideo.shouldOptimizeForNetworkUse = true
                        exportVideo.exportAsynchronously { [weak self] in
                            let success = exportVideo.status == .completed
                            if !success {
                                try? FileManager.default.copyItem(at: rawTemp, to: videoDst)
                            }
                            try? FileManager.default.removeItem(at: rawTemp)

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
                            let transAsset = AVURLAsset(url: videoDst)
                            if let exportAudio = AVAssetExportSession(asset: transAsset, presetName: AVAssetExportPresetAppleM4A) {
                                try? FileManager.default.removeItem(at: audioDst)
                                exportAudio.outputURL = audioDst
                                exportAudio.outputFileType = .m4a
                                exportAudio.exportAsynchronously { [weak self] in
                                    if exportAudio.status == .completed {
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
                    } else {
                        try? FileManager.default.copyItem(at: rawTemp, to: videoDst)
                        try? FileManager.default.removeItem(at: rawTemp)
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

struct NativeLiquidGlassBottomBar: View {
    @ObservedObject var viewModel: WebViewModel
    @Namespace private var glassNamespace
    
    var body: some View {
        if #available(iOS 26.0, *) {
            glassBar26
        } else {
            fallbackBar
        }
    }
    
    @available(iOS 26.0, *)
    private var glassBar26: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                capsuleContent26
                    .glassEffect(.regular.interactive(), in: Capsule())
                
                actionButton
                    .glassEffect(.regular.interactive(), in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
    
    private var fallbackBar: some View {
        HStack(spacing: 12) {
            capsuleContentFallback
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                )
            
            actionButton
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
    
    @available(iOS 26.0, *)
    private var capsuleContent26: some View {
        let totalWidth: CGFloat = 196
        let height: CGFloat = 54
        
        return HStack(spacing: 0) {
            tabItem26(title: "Рацион", icon: "fork.knife", key: "diet")
            tabItem26(title: "Трени", icon: "dumbbell.fill", key: "split")
        }
        .frame(width: totalWidth, height: height)
        .contentShape(Capsule())
        .gesture(capsuleDragGesture(totalWidth: totalWidth))
    }
    
    @available(iOS 26.0, *)
    @ViewBuilder
    private func tabItem26(title: String, icon: String, key: String) -> some View {
        let isSelected = viewModel.currentView == key
        let accentColor = Color(hex: viewModel.accentHex)
        
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? accentColor : Color(white: 0.55))
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : Color(white: 0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(4)
        .background {
            if isSelected {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .matchedGeometryEffect(id: "activeTabIndicator", in: glassNamespace)
            }
        }
        .glassEffectID(isSelected ? "activeTab" : nil, in: glassNamespace)
    }
    
    private var capsuleContentFallback: some View {
        let totalWidth: CGFloat = 196
        let height: CGFloat = 54
        
        return HStack(spacing: 0) {
            tabItemFallback(title: "Рацион", icon: "fork.knife", key: "diet")
            tabItemFallback(title: "Трени", icon: "dumbbell.fill", key: "split")
        }
        .frame(width: totalWidth, height: height)
        .contentShape(Capsule())
        .gesture(capsuleDragGesture(totalWidth: totalWidth))
    }
    
    @ViewBuilder
    private func tabItemFallback(title: String, icon: String, key: String) -> some View {
        let isSelected = viewModel.currentView == key
        let accentColor = Color(hex: viewModel.accentHex)
        
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? accentColor : Color(white: 0.55))
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : Color(white: 0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(4)
        .background {
            if isSelected {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .matchedGeometryEffect(id: "activeTabIndicatorFallback", in: glassNamespace)
            }
        }
    }
    
    private func capsuleDragGesture(totalWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let target = value.location.x < (totalWidth / 2.0) ? "diet" : "split"
                if viewModel.currentView != target {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        viewModel.navigate(to: target)
                    }
                }
            }
    }
    
    private var actionButton: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            viewModel.handleTopRightAction()
        }) {
            Image(systemName: viewModel.currentView == "diet" ? "viewfinder" : "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 54, height: 54)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
}

struct ContentView: View {
    @ObservedObject private var viewModel = WebViewModel.shared
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(red: 0.03, green: 0.03, blue: 0.04).ignoresSafeArea()
            WebView().ignoresSafeArea(.container, edges: .vertical)
            
            NativeLiquidGlassBottomBar(viewModel: viewModel)
                .opacity(viewModel.isModalOpen ? 0 : 1)
                .offset(y: viewModel.isModalOpen ? 100 : 0)
                .animation(.spring(response: 0.32, dampingFraction: 0.85), value: viewModel.isModalOpen)
                .allowsHitTesting(!viewModel.isModalOpen)
                .ignoresSafeArea(.keyboard, edges: .bottom)
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
