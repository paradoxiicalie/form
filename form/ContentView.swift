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
    var isPageLoaded: Bool = false
    
    @Published var currentView: String = "diet"
    @Published var isModalOpen: Bool = false
    @Published var accentHex: String = {
        let d = UserDefaults(suiteName: "group.com.macro.shared")
        return d?.string(forKey: "barAccentHex") ?? d?.string(forKey: "calHex") ?? "#D62828"
    }()
    
    func navigate(to route: String, animated: Bool = true) {
        let performNavigation = {
            if self.currentView != route {
                if animated {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        self.currentView = route
                    }
                } else {
                    self.currentView = route
                }
            }
            if let wv = self.webView {
                let escapedRoute = route.replacingOccurrences(of: "'", with: "\\'")
                let js = """
                (function() {
                    var fn = (typeof window.switchMainView === 'function') ? window.switchMainView : ((typeof switchMainView === 'function') ? switchMainView : null);
                    if (fn) {
                        fn('\(escapedRoute)', false, true);
                        return 'OK';
                    }
                    return 'PENDING';
                })();
                """
                wv.evaluateJavaScript(js) { result, error in
                    if let status = result as? String, status == "OK" {
                        self.isPageLoaded = true
                        if self.pendingRoute == route {
                            self.pendingRoute = nil
                        }
                    } else {
                        self.pendingRoute = route
                        if let error = error {
                            print("[Form][NativeBar] navigate('\(route)') JS error: \(error.localizedDescription)")
                        }
                    }
                }
            } else {
                self.pendingRoute = route
                print("[Form][NativeBar] navigate('\(route)') queued: waiting for webView")
            }
        }
        if Thread.isMainThread {
            performNavigation()
        } else {
            DispatchQueue.main.async(execute: performNavigation)
        }
    }
    
    func handleTopRightAction() {
        DispatchQueue.main.async {
            guard let wv = self.webView else {
                print("[Form][NativeBar] handleTopRightAction aborted: webView is nil")
                return
            }
            let activeView = self.currentView
            let js: String
            if activeView == "split" {
                js = """
                (function() {
                    try {
                        if (typeof window.openAddExerciseModal === 'function') {
                            window.openAddExerciseModal();
                        } else if (typeof openAddExerciseModal === 'function') {
                            openAddExerciseModal();
                        } else if (typeof window.handleTopRightAction === 'function') {
                            window.handleTopRightAction();
                        } else {
                            return 'MISSING_FN:openAddExerciseModal';
                        }
                        if (typeof window.checkModalVisibilityToNative === 'function') {
                            window.checkModalVisibilityToNative();
                        }
                        return 'OK:split';
                    } catch (e) {
                        return 'JS_ERR:' + (e && e.message ? e.message : String(e));
                    }
                })();
                """
            } else {
                js = """
                (function() {
                    try {
                        if (typeof window.openScanner === 'function') {
                            window.openScanner('auto');
                        } else if (typeof openScanner === 'function') {
                            openScanner('auto');
                        } else if (typeof window.handleTopRightAction === 'function') {
                            window.handleTopRightAction();
                        } else {
                            return 'MISSING_FN:openScanner';
                        }
                        if (typeof window.checkModalVisibilityToNative === 'function') {
                            window.checkModalVisibilityToNative();
                        }
                        return 'OK:diet';
                    } catch (e) {
                        return 'JS_ERR:' + (e && e.message ? e.message : String(e));
                    }
                })();
                """
            }
            wv.evaluateJavaScript(js) { result, error in
                if let error = error {
                    print("[Form][NativeBar] handleTopRightAction(\(activeView)) JS error: \(error.localizedDescription)")
                } else if let status = result as? String, !status.hasPrefix("OK:") {
                    print("[Form][NativeBar] handleTopRightAction(\(activeView)) warning: \(status)")
                }
            }
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
                DispatchQueue.main.async {
                    RestActivityManager.shared.stopActivity()
                }
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
                DispatchQueue.main.async {
                    RestActivityManager.shared.stopActivity()
                }
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
    
    private static let diskBackupQueue = DispatchQueue(label: "com.form.diskbackup.serial", qos: .utility)

    static var diskBackupURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("form_state_backup.json")
    }

    static func jsJSONLiteral(from object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              var json = String(data: data, encoding: .utf8) else {
            return nil
        }
        json = json
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return json
    }

    static func jsStringLiteral(_ raw: String) -> String {
        if let encodedArray = jsJSONLiteral(from: [raw]), encodedArray.count >= 2 {
            let start = encodedArray.index(after: encodedArray.startIndex)
            let end = encodedArray.index(before: encodedArray.endIndex)
            return String(encodedArray[start..<end])
        }
        return "\"\""
    }

    @discardableResult
    static func writeDiskBackupSync(_ jsonString: String) -> Bool {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else { return false }
        do {
            try data.write(to: diskBackupURL, options: .atomic)
            guard FileManager.default.fileExists(atPath: diskBackupURL.path) else { return false }
            if let d = UserDefaults(suiteName: "group.com.macro.shared") {
                if d.object(forKey: "formNativeBackupJSON") != nil {
                    d.removeObject(forKey: "formNativeBackupJSON")
                }
                if d.object(forKey: "nativeStateJson") != nil {
                    d.removeObject(forKey: "nativeStateJson")
                }
            }
            return true
        } catch {
            print("[Form][Backup] writeDiskBackupSync error: \(error.localizedDescription)")
            return false
        }
    }

    static func saveDiskBackup(jsonString: String) {
        let copy = jsonString
        diskBackupQueue.async {
            _ = writeDiskBackupSync(copy)
        }
    }

    static func loadDiskBackup() -> String? {
        guard FileManager.default.fileExists(atPath: diskBackupURL.path),
              let data = try? Data(contentsOf: diskBackupURL),
              let str = String(data: data, encoding: .utf8),
              !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return str
    }

    private static func inspectBackupCandidate(_ jsonString: String?) -> (valid: Bool, updatedAt: Double?, score: Int) {
        guard let raw = jsonString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return (false, nil, 0)
        }
        let updatedAt = (dict["updatedAt"] as? NSNumber)?.doubleValue
        var score = 0
        if let todayItems = dict["todayItems"] as? [Any] { score += todayItems.count }
        if let history = dict["history"] as? [String: Any] { score += history.count * 5 }
        if let customHistory = dict["customHistory"] as? [Any] { score += customHistory.count }
        if let weightLogs = dict["weightLogs"] as? [Any] { score += weightLogs.count * 3 }
        if let workout = dict["workout"] as? [String: Any] {
            if let logs = workout["logs"] as? [Any] { score += logs.count * 2 }
            if let notes = workout["exerciseNotes"] as? [String: Any] { score += notes.count * 10 }
        }
        return (true, updatedAt, score)
    }

    static func resolveBestNativeBackup() -> String? {
        let sharedDefaults = UserDefaults(suiteName: "group.com.macro.shared")
        let defaultsStr = sharedDefaults?.string(forKey: "nativeStateJson") ?? sharedDefaults?.string(forKey: "formNativeBackupJSON")
        let diskStr = diskBackupQueue.sync { loadDiskBackup() }

        let diskInfo = inspectBackupCandidate(diskStr)
        let defaultsInfo = inspectBackupCandidate(defaultsStr)

        var chosen: String? = nil
        if diskInfo.valid && !defaultsInfo.valid {
            chosen = diskStr
        } else if !diskInfo.valid && defaultsInfo.valid {
            chosen = defaultsStr
        } else if diskInfo.valid && defaultsInfo.valid {
            if let dTs = diskInfo.updatedAt, let uTs = defaultsInfo.updatedAt {
                chosen = (dTs >= uTs) ? diskStr : defaultsStr
            } else if diskInfo.updatedAt != nil {
                chosen = diskStr
            } else if defaultsInfo.updatedAt != nil {
                chosen = defaultsStr
            } else {
                chosen = (diskInfo.score >= defaultsInfo.score) ? diskStr : defaultsStr
            }
        }

        if let winner = chosen,
           let rawDef = defaultsStr, !rawDef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let needsDiskWrite = (winner != diskStr)
            diskBackupQueue.sync {
                if needsDiskWrite || !FileManager.default.fileExists(atPath: diskBackupURL.path) {
                    _ = writeDiskBackupSync(winner)
                } else {
                    sharedDefaults?.removeObject(forKey: "formNativeBackupJSON")
                    sharedDefaults?.removeObject(forKey: "nativeStateJson")
                }
            }
        }
        return chosen
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
        // Не удаляем свежие (<10 мин) или временные raw-файлы, чтобы не задеть активный импорт/транскодинг
        let normalized = Set(activeFileNames.map { extractMediaFileName(from: $0) }.filter { !$0.isEmpty })
        let dir = notesMediaDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        let now = Date()
        let protectionWindowSeconds: TimeInterval = 600
        for file in files {
            guard !file.hasPrefix("."), !file.hasPrefix("raw_") else { continue }
            if !normalized.contains(file) {
                let fileURL = dir.appendingPathComponent(file)
                if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path) {
                    let modDate = (attrs[.modificationDate] as? Date) ?? (attrs[.creationDate] as? Date)
                    if let d = modDate, now.timeIntervalSince(d) < protectionWindowSeconds {
                        continue
                    }
                    if let cDate = attrs[.creationDate] as? Date, now.timeIntervalSince(cDate) < protectionWindowSeconds {
                        continue
                    }
                }
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    private func deliverMediaResponse(for urlSchemeTask: WKURLSchemeTask, url: URL, statusCode: Int, headers: [String: String], data: Data) {
        DispatchQueue.main.async {
            if self.isTaskActive(urlSchemeTask) {
                if let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers) {
                    urlSchemeTask.didReceive(response)
                    if self.isTaskActive(urlSchemeTask) {
                        urlSchemeTask.didReceive(data)
                    }
                    if self.isTaskActive(urlSchemeTask) {
                        urlSchemeTask.didFinish()
                    }
                } else {
                    urlSchemeTask.didFailWithError(NSError(domain: "FormMedia", code: 500, userInfo: nil))
                }
            }
            self.unregisterTask(urlSchemeTask)
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
        
        let rangeHeader = urlSchemeTask.request.value(forHTTPHeaderField: "Range")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, self.isTaskActive(urlSchemeTask) else { return }
            
            let fileName = Self.extractMediaFileName(from: url)
            guard let fileURL = Self.resolveMediaFileURL(rawUrlOrName: fileName),
                  let attr = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let fileSize = attr[.size] as? UInt64, fileSize > 0 else {
                DispatchQueue.main.async {
                    if self.isTaskActive(urlSchemeTask) {
                        let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Access-Control-Allow-Origin": "*"])
                        if let resp = resp {
                            urlSchemeTask.didReceive(resp)
                        }
                        urlSchemeTask.didFailWithError(NSError(domain: "FormMedia", code: 404, userInfo: [NSLocalizedDescriptionKey: "File not found"]))
                    }
                    self.unregisterTask(urlSchemeTask)
                }
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
                DispatchQueue.main.async {
                    if self.isTaskActive(urlSchemeTask) {
                        urlSchemeTask.didFailWithError(NSError(domain: "FormMedia", code: 500, userInfo: nil))
                    }
                    self.unregisterTask(urlSchemeTask)
                }
                return
            }
            defer { try? fileHandle.close() }
            
            // Поддержка HTTP Range через FileHandle: читаем ровно запрошенный чанк без выгрузки гигабайтов в RAM
            if let rangeHeader = rangeHeader,
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
                self.deliverMediaResponse(for: urlSchemeTask, url: url, statusCode: 206, headers: headers, data: subData)
                return
            }
            
            let data = fileHandle.readDataToEndOfFile()
            let headers: [String: String] = [
                "Content-Type": mimeType,
                "Content-Length": "\(totalSize)",
                "Accept-Ranges": "bytes",
                "Access-Control-Allow-Origin": "*"
            ]
            self.deliverMediaResponse(for: urlSchemeTask, url: url, statusCode: 200, headers: headers, data: data)
        }
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        unregisterTask(urlSchemeTask)
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
        super.init()
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

struct WebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "widgetBridge")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "iosBridge")
        coordinator.stopMonitoring()
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationDelegate.shared
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.setURLSchemeHandler(FormMediaSchemeHandler(), forURLScheme: "form-media")
        
        WebViewModel.shared.isPageLoaded = false
        WebViewModel.shared.isModalOpen = false
        let initialRoute = WebViewModel.shared.pendingRoute ?? WebViewModel.shared.currentView
        WebViewModel.shared.pendingRoute = nil
        if WebViewModel.shared.currentView != initialRoute {
            WebViewModel.shared.currentView = initialRoute
        }
        let initialRouteLiteral = FormMediaSchemeHandler.jsStringLiteral(initialRoute)

        let sharedDefaults = UserDefaults(suiteName: "group.com.macro.shared")
        let savedKey = sharedDefaults?.string(forKey: "nativeApiKey") ?? ""
        let stoppedExternally = sharedDefaults?.bool(forKey: "restTimerStoppedExternally") ?? false
        if stoppedExternally {
            sharedDefaults?.set(false, forKey: "restTimerStoppedExternally")
            sharedDefaults?.set(0.0, forKey: "restTimerEndDate")
            sharedDefaults?.synchronize()
            if #available(iOS 16.2, *) {
                RestActivityManager.shared.stopActivity()
            }
        }
        let savedState = FormMediaSchemeHandler.resolveBestNativeBackup() ?? ""
        let keyLiteral = FormMediaSchemeHandler.jsStringLiteral(savedKey)
        let stateJsonStringLiteral = savedState.isEmpty ? "null" : FormMediaSchemeHandler.jsStringLiteral(savedState)

        let preloadJS = """
        window.__NATIVE_API_KEY__ = \(keyLiteral);
        window.__INITIAL_ROUTE__ = \(initialRouteLiteral);
        window.__REST_TIMER_STOPPED_EXTERNALLY__ = \(stoppedExternally ? "true" : "false");
        (function() {
            try {
                var raw = \(stateJsonStringLiteral);
                window.__NATIVE_STATE__ = (typeof raw === 'string' && raw) ? JSON.parse(raw) : null;
            } catch (e) {
                window.__NATIVE_STATE__ = null;
            }
        })();
        """
        let userScript = WKUserScript(source: preloadJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)
        let weakBridge = WeakScriptMessageHandler(delegate: context.coordinator)
        config.userContentController.add(weakBridge, name: "widgetBridge")
        config.userContentController.add(weakBridge, name: "iosBridge")
        
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
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if WebViewModel.shared.webView !== uiView {
            WebViewModel.shared.webView = uiView
        }
        if context.coordinator.currentWebView !== uiView {
            context.coordinator.currentWebView = uiView
        }
    }
    
    class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler, PHPickerViewControllerDelegate {
        private let pedometer = CMPedometer()
        weak var currentWebView: WKWebView?
        var pendingNoteId: String = ""
        var pendingExName: String = ""
        private var notificationTokens: [NSObjectProtocol] = []
        
        private static let stopRestTimerJS = """
            if (typeof stopRestTimer === 'function') { stopRestTimer(true); }
            if (typeof closeRestTimer === 'function') { closeRestTimer(); }
            if (typeof cancelRestTimer === 'function') { cancelRestTimer(); }
            var bar = document.getElementById('restTimerFloatingBar');
            if (bar) { bar.classList.add('hidden'); }
            if (typeof window.onRestTimerStopped === 'function') { window.onRestTimerStopped(); }
        """
        
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
            
            let t1 = NotificationCenter.default.addObserver(forName: Notification.Name("FormStopRestTimerExternally"), object: nil, queue: .main) { [weak webView, weak self] _ in
                self?.cancelRestNotification()
                if #available(iOS 16.2, *) {
                    RestActivityManager.shared.stopActivity()
                }
                if let d = UserDefaults(suiteName: "group.com.macro.shared") {
                    d.set(0.0, forKey: "restTimerEndDate")
                    d.set(false, forKey: "restTimerStoppedExternally")
                    d.synchronize()
                    WidgetCenter.shared.reloadAllTimelines()
                }
                webView?.evaluateJavaScript(Self.stopRestTimerJS, completionHandler: nil)
            }
            
            let t2 = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak webView, weak self] _ in
                guard let d = UserDefaults(suiteName: "group.com.macro.shared"),
                      d.bool(forKey: "restTimerStoppedExternally") else { return }
                d.set(false, forKey: "restTimerStoppedExternally")
                d.set(0.0, forKey: "restTimerEndDate")
                d.synchronize()
                self?.cancelRestNotification()
                if #available(iOS 16.2, *) {
                    RestActivityManager.shared.stopActivity()
                }
                WidgetCenter.shared.reloadAllTimelines()
                webView?.evaluateJavaScript(Self.stopRestTimerJS, completionHandler: nil)
            }
            notificationTokens = [t1, t2]
        }
        
        func removeNotificationObservers() {
            for token in notificationTokens {
                NotificationCenter.default.removeObserver(token)
            }
            notificationTokens.removeAll()
        }
        
        func stopMonitoring() {
            pedometer.stopUpdates()
            NotificationCenter.default.removeObserver(self)
            removeNotificationObservers()
        }
        
        deinit {
            stopMonitoring()
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

        private func markPageReadyAndFlushPendingRoute(webView: WKWebView) {
            self.currentWebView = webView
            WebViewModel.shared.isPageLoaded = true
            WebViewModel.shared.isModalOpen = false
            if let route = WebViewModel.shared.pendingRoute {
                WebViewModel.shared.pendingRoute = nil
                let escapedRoute = route.replacingOccurrences(of: "'", with: "\\'")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    webView.evaluateJavaScript("if (typeof window.switchMainView === 'function') { window.switchMainView('\(escapedRoute)', true, true); } else if (typeof switchMainView === 'function') { switchMainView('\(escapedRoute)', true, true); }", completionHandler: nil)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            markPageReadyAndFlushPendingRoute(webView: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            markPageReadyAndFlushPendingRoute(webView: webView)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            markPageReadyAndFlushPendingRoute(webView: webView)
            if let d = UserDefaults(suiteName: "group.com.macro.shared"),
               d.bool(forKey: "restTimerStoppedExternally") {
                d.set(false, forKey: "restTimerStoppedExternally")
                d.set(0.0, forKey: "restTimerEndDate")
                d.synchronize()
                cancelRestNotification()
                if #available(iOS 16.2, *) {
                    RestActivityManager.shared.stopActivity()
                }
                WidgetCenter.shared.reloadAllTimelines()
                webView.evaluateJavaScript(Self.stopRestTimerJS, completionHandler: nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.syncStepsSilently(webView: webView)
            }
            // Восстанавливаем базу из нативного бэкапа без задержек, если localStorage и первичная загрузка пусты
            if let json = FormMediaSchemeHandler.resolveBestNativeBackup(), !json.isEmpty {
                let jsonStringLiteral = FormMediaSchemeHandler.jsStringLiteral(json)
                webView.evaluateJavaScript("""
                    (function(){
                        if (window._stateLoadedFromStorage) { return; }
                        var KEYS = ['macro_minimal_ios_v9','macro_minimal_ios_v8','macro_minimal_ios_v7'];
                        var hasData = KEYS.some(function(k){ var v = localStorage.getItem(k); return v && v.length > 50; });
                        if (!hasData) {
                            try {
                                var json = \(jsonStringLiteral);
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

            if !WebViewModel.shared.isPageLoaded {
                WebViewModel.shared.isPageLoaded = true
                if let route = WebViewModel.shared.pendingRoute {
                    WebViewModel.shared.pendingRoute = nil
                    let escapedRoute = route.replacingOccurrences(of: "'", with: "\\'")
                    DispatchQueue.main.async { [weak wv = message.webView] in
                        wv?.evaluateJavaScript("if (typeof window.switchMainView === 'function') { window.switchMainView('\(escapedRoute)', true, true); } else if (typeof switchMainView === 'function') { switchMainView('\(escapedRoute)', true, true); }", completionHandler: nil)
                    }
                }
            }
            
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
                    UserDefaults(suiteName: "group.com.macro.shared")?.set(hex, forKey: "barAccentHex")
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
                let totalSeconds = dict["totalSeconds"] as? Double ?? seconds
                let text = dict["text"] as? String ?? "Отдых окончен! Время подхода."
                let exName = dict["exerciseName"] as? String ?? "Подход"
                let themeCalHex = dict["themeCalHex"] as? String ?? "#D62828"
                scheduleRestNotification(seconds: seconds, text: text)
                if let d = UserDefaults(suiteName: "group.com.macro.shared") {
                    let endMs = Date().addingTimeInterval(max(1.0, seconds)).timeIntervalSince1970 * 1000.0
                    d.set(endMs, forKey: "restTimerEndDate")
                    d.set(false, forKey: "restTimerStoppedExternally")
                    d.synchronize()
                    WidgetCenter.shared.reloadAllTimelines()
                }
                let wv = message.webView
                RestActivityManager.shared.startActivity(
                    seconds: seconds,
                    totalSeconds: totalSeconds,
                    exerciseName: exName,
                    themeCalHex: themeCalHex
                ) {
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
                }
                return
            }
            guard let d = UserDefaults(suiteName: "group.com.macro.shared") else { return }
            if let apiKey = dict["apiKey"] as? String { d.set(apiKey, forKey: "nativeApiKey") }
            if let stateJson = dict["stateJson"] as? String, !stateJson.isEmpty {
                FormMediaSchemeHandler.saveDiskBackup(jsonString: stateJson)
            }
            if let calHex = dict["calHex"] as? String {
                d.set(calHex, forKey: "calHex")
            }
            let barAccent = (dict["accentHex"] as? String) ?? (dict["calHex"] as? String)
            if let barAccent = barAccent, !barAccent.isEmpty {
                d.set(barAccent, forKey: "barAccentHex")
                DispatchQueue.main.async {
                    if WebViewModel.shared.accentHex != barAccent {
                        WebViewModel.shared.accentHex = barAccent
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
                    let reqIdLit = FormMediaSchemeHandler.jsStringLiteral(reqId)
                    let respLit = FormMediaSchemeHandler.jsStringLiteral(respDataString)
                    let errLit = errString.isEmpty ? "null" : FormMediaSchemeHandler.jsStringLiteral(errString)
                    let js = """
                    if (typeof window.onNativeFetchGeminiResult === 'function') {
                        window.onNativeFetchGeminiResult(\(reqIdLit), \(statusCode), \(respLit), \(errLit));
                    }
                    """
                    webView?.evaluateJavaScript(js, completionHandler: nil)
                }
            }.resume()
        }

        private func emitNoteMediaJS(functionName: String, payload: [String: Any], webView: WKWebView?) {
            guard let jsonPayload = FormMediaSchemeHandler.jsJSONLiteral(from: payload) else { return }
            let js = "if (typeof window.\(functionName) === 'function') { window.\(functionName)(\(jsonPayload)); }"
            DispatchQueue.main.async {
                webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else {
                emitNoteMediaJS(functionName: "onNoteMediaPicked", payload: ["cancelled": true], webView: self.currentWebView)
                return
            }

            let noteId = self.pendingNoteId
            let exName = self.pendingExName
            let uuid = UUID().uuidString
            let mediaDir = FormMediaSchemeHandler.notesMediaDirectory
            let tmpDir = FileManager.default.temporaryDirectory
            let isVideo = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)

            emitNoteMediaJS(
                functionName: "onNoteMediaLoading",
                payload: ["type": isVideo ? "video" : "photo", "exName": exName],
                webView: self.currentWebView
            )

            if isVideo {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] tempUrl, error in
                    guard let tempUrl = tempUrl, error == nil else {
                        self?.emitNoteMediaJS(
                            functionName: "onNoteMediaPicked",
                            payload: ["error": "Не удалось загрузить видео"],
                            webView: self?.currentWebView
                        )
                        return
                    }

                    let rawTemp = tmpDir.appendingPathComponent("raw_\(uuid).mov")
                    let tempVideoOut = tmpDir.appendingPathComponent("video_tmp_\(uuid).mp4")
                    let videoDst = mediaDir.appendingPathComponent("video_\(uuid).mp4")
                    let tempAudioOut = tmpDir.appendingPathComponent("audio_tmp_\(uuid).m4a")
                    let audioDst = mediaDir.appendingPathComponent("audio_\(uuid).m4a")
                    let thumbDst = mediaDir.appendingPathComponent("thumb_\(uuid).jpg")

                    try? FileManager.default.removeItem(at: rawTemp)
                    try? FileManager.default.removeItem(at: tempVideoOut)
                    try? FileManager.default.removeItem(at: tempAudioOut)
                    try? FileManager.default.copyItem(at: tempUrl, to: rawTemp)

                    let asset = AVURLAsset(url: rawTemp)
                    let duration = CMTimeGetSeconds(asset.duration)

                    let gen = AVAssetImageGenerator(asset: asset)
                    gen.appliesPreferredTrackTransform = true
                    let time = CMTime(seconds: 0.1, preferredTimescale: 600)
                    if let imageRef = try? gen.copyCGImage(at: time, actualTime: nil) {
                        let thumbImg = UIImage(cgImage: imageRef)
                        if let thumbData = thumbImg.jpegData(compressionQuality: 0.75) {
                            try? thumbData.write(to: thumbDst, options: .atomic)
                        }
                    }

                    let publishAndExtractAudio: () -> Void = { [weak self] in
                        let durValue = duration.isNaN ? 0.0 : duration
                        var pickedPayload: [String: Any] = [
                            "success": true,
                            "noteId": noteId,
                            "exName": exName,
                            "type": "video",
                            "url": "form-media://video_\(uuid).mp4",
                            "audioUrl": NSNull(),
                            "thumbUrl": FileManager.default.fileExists(atPath: thumbDst.path) ? "form-media://thumb_\(uuid).jpg" : NSNull(),
                            "duration": durValue
                        ]
                        self?.emitNoteMediaJS(functionName: "onNoteMediaPicked", payload: pickedPayload, webView: self?.currentWebView)

                        let transAsset = AVURLAsset(url: videoDst)
                        if let exportAudio = AVAssetExportSession(asset: transAsset, presetName: AVAssetExportPresetAppleM4A) {
                            exportAudio.outputURL = tempAudioOut
                            exportAudio.outputFileType = .m4a
                            exportAudio.exportAsynchronously { [weak self] in
                                if exportAudio.status == .completed,
                                   FileManager.default.fileExists(atPath: tempAudioOut.path) {
                                    try? FileManager.default.removeItem(at: audioDst)
                                    do {
                                        try FileManager.default.moveItem(at: tempAudioOut, to: audioDst)
                                        self?.emitNoteMediaJS(
                                            functionName: "onNoteAudioExtracted",
                                            payload: [
                                                "noteId": noteId,
                                                "videoUrl": "form-media://video_\(uuid).mp4",
                                                "audioUrl": "form-media://audio_\(uuid).m4a"
                                            ],
                                            webView: self?.currentWebView
                                        )
                                    } catch {
                                        try? FileManager.default.removeItem(at: tempAudioOut)
                                    }
                                } else {
                                    try? FileManager.default.removeItem(at: tempAudioOut)
                                }
                            }
                        }
                    }

                    // Аппаратное транскодирование в temporaryDirectory -> перенос готового файла в NotesMedia
                    try? FileManager.default.removeItem(at: videoDst)
                    if let exportVideo = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) {
                        exportVideo.outputURL = tempVideoOut
                        exportVideo.outputFileType = .mp4
                        exportVideo.shouldOptimizeForNetworkUse = true
                        exportVideo.exportAsynchronously {
                            let success = exportVideo.status == .completed && FileManager.default.fileExists(atPath: tempVideoOut.path)
                            if success {
                                try? FileManager.default.moveItem(at: tempVideoOut, to: videoDst)
                            } else {
                                try? FileManager.default.removeItem(at: tempVideoOut)
                                try? FileManager.default.copyItem(at: rawTemp, to: videoDst)
                            }
                            try? FileManager.default.removeItem(at: rawTemp)
                            publishAndExtractAudio()
                        }
                    } else {
                        try? FileManager.default.copyItem(at: rawTemp, to: videoDst)
                        try? FileManager.default.removeItem(at: rawTemp)
                        publishAndExtractAudio()
                    }
                }
            } else if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                    guard let image = object as? UIImage, error == nil else {
                        self?.emitNoteMediaJS(
                            functionName: "onNoteMediaPicked",
                            payload: ["error": "Не удалось загрузить фото"],
                            webView: self?.currentWebView
                        )
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
                        try? jpegData.write(to: photoDst, options: .atomic)
                    }

                    self?.emitNoteMediaJS(
                        functionName: "onNoteMediaPicked",
                        payload: [
                            "success": true,
                            "noteId": noteId,
                            "exName": exName,
                            "type": "photo",
                            "url": "form-media://photo_\(uuid).jpg",
                            "thumbUrl": "form-media://photo_\(uuid).jpg"
                        ],
                        webView: self?.currentWebView
                    )
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
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .contentShape(Capsule())
                
                actionButton26
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
                .contentShape(Capsule())
            
            actionButtonFallback
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
    
    @available(iOS 26.0, *)
    private var capsuleContent26: some View {
        let totalWidth: CGFloat = 196
        let height: CGFloat = 56
        let pillWidth = (totalWidth - 8) / 2.0
        
        return ZStack {
            Capsule()
                .fill(Color.black.opacity(0.015))
            Capsule()
                .fill(Color.white.opacity(0.16))
                .frame(width: pillWidth, height: height - 8)
                .offset(x: viewModel.currentView == "diet" ? -(pillWidth / 2.0) : (pillWidth / 2.0))
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: viewModel.currentView)
            HStack(spacing: 0) {
                tabItem26(title: "Рацион", icon: "fork.knife", key: "diet")
                tabItem26(title: "Трени", icon: "dumbbell.fill", key: "split")
            }
        }
        .frame(width: totalWidth, height: height)
        .contentShape(Capsule())
        .simultaneousGesture(capsuleDragGesture(totalWidth: totalWidth))
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
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.currentView != key {
                UISelectionFeedbackGenerator().selectionChanged()
                viewModel.navigate(to: key)
            }
        }
    }
    
    private var capsuleContentFallback: some View {
        let totalWidth: CGFloat = 196
        let height: CGFloat = 56
        let pillWidth = (totalWidth - 8) / 2.0
        
        return ZStack {
            Capsule()
                .fill(Color.black.opacity(0.015))
            Capsule()
                .fill(Color.white.opacity(0.16))
                .frame(width: pillWidth, height: height - 8)
                .offset(x: viewModel.currentView == "diet" ? -(pillWidth / 2.0) : (pillWidth / 2.0))
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: viewModel.currentView)
            HStack(spacing: 0) {
                tabItemFallback(title: "Рацион", icon: "fork.knife", key: "diet")
                tabItemFallback(title: "Трени", icon: "dumbbell.fill", key: "split")
            }
        }
        .frame(width: totalWidth, height: height)
        .contentShape(Capsule())
        .simultaneousGesture(capsuleDragGesture(totalWidth: totalWidth))
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
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.currentView != key {
                UISelectionFeedbackGenerator().selectionChanged()
                viewModel.navigate(to: key)
            }
        }
    }
    
    private func capsuleDragGesture(totalWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard value.location.y >= -24 && value.location.y <= 80 else { return }
                let target = value.location.x < (totalWidth / 2.0) ? "diet" : "split"
                if viewModel.currentView != target {
                    UISelectionFeedbackGenerator().selectionChanged()
                    viewModel.navigate(to: target)
                }
            }
    }
    
    @available(iOS 26.0, *)
    private var actionButton26: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.handleTopRightAction()
        }) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.015))
                Image(systemName: viewModel.currentView == "diet" ? "viewfinder" : "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 56, height: 56)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .frame(width: 56, height: 56)
        .contentShape(Circle())
        .accessibilityLabel(viewModel.currentView == "diet" ? "Сканер продуктов" : "Добавить упражнение")
    }
    
    private var actionButtonFallback: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.handleTopRightAction()
        }) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.015))
                Image(systemName: viewModel.currentView == "diet" ? "viewfinder" : "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 56, height: 56)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 56, height: 56)
        .contentShape(Circle())
        .accessibilityLabel(viewModel.currentView == "diet" ? "Сканер продуктов" : "Добавить упражнение")
    }
}

struct ContentView: View {
    @ObservedObject private var viewModel = WebViewModel.shared
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(red: 0.03, green: 0.03, blue: 0.04).ignoresSafeArea()
            WebView().ignoresSafeArea(.container, edges: .vertical)
            
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                NativeLiquidGlassBottomBar(viewModel: viewModel)
                    .opacity(viewModel.isModalOpen ? 0 : 1)
                    .offset(y: viewModel.isModalOpen ? 100 : 0)
                    .animation(.spring(response: 0.32, dampingFraction: 0.85), value: viewModel.isModalOpen)
                    .allowsHitTesting(!viewModel.isModalOpen)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .zIndex(10)
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
