import SwiftUI
import WebKit
import Network

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

struct ContentView: View {
    @AppStorage("windowsWifiUrl") private var windowsWifiUrl: String = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var showWifiPrompt = false
    @State private var urlDraft = ""
    @State private var themeBgHex = "#f5f5f7"
    @State private var isDarkTheme = false
    @State private var syncPulse = 0

    var body: some View {
        ZStack {
            Color(hex: themeBgHex)
                .ignoresSafeArea(.all)

            BooksWebView(
                wifiServerUrl: windowsWifiUrl,
                syncPulse: syncPulse,
                onOpenWifiConfig: {
                    urlDraft = windowsWifiUrl
                    showWifiPrompt = true
                },
                onThemeChange: { hex, dark in
                    themeBgHex = hex
                    isDarkTheme = dark
                }
            )
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .preferredColorScheme(isDarkTheme ? .dark : .light)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                syncPulse += 1
            }
        }
        .alert("Pair with Windows PC (One-Time Setup)", isPresented: $showWifiPrompt) {
            TextField("192.168.1.42:8765", text: $urlDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save & Auto-Sync") {
                var cleaned = urlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                while cleaned.hasSuffix("/") { cleaned.removeLast() }
                if !cleaned.isEmpty && !cleaned.lowercased().hasPrefix("http://") && !cleaned.lowercased().hasPrefix("https://") {
                    cleaned = "http://" + cleaned
                }
                windowsWifiUrl = cleaned
                syncPulse += 1
            }
            Button("Disconnect PC", role: .destructive) {
                windowsWifiUrl = ""
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter your Windows PC link once. This app always works offline and will auto-sync whenever you're back on home Wi-Fi.")
        }
    }
}

struct BooksWebView: UIViewRepresentable {
    let wifiServerUrl: String
    let syncPulse: Int
    let onOpenWifiConfig: () -> Void
    let onThemeChange: (String, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenWifiConfig: onOpenWifiConfig, onThemeChange: onThemeChange)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "booksBridge")
        contentController.add(context.coordinator, name: "booksSaveMeta")
        contentController.add(context.coordinator, name: "booksSaveLibrary")
        contentController.add(context.coordinator, name: "booksTheme")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        context.coordinator.webView = webView
        context.coordinator.wifiServerUrl = wifiServerUrl
        context.coordinator.startNetworkMonitor()

        // ALWAYS load bundled local index.html — opens instantly even when Windows PC is turned off!
        if let localHtml = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(localHtml, allowingReadAccessTo: localHtml.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let changed = context.coordinator.wifiServerUrl != wifiServerUrl
        context.coordinator.wifiServerUrl = wifiServerUrl
        if changed || syncPulse > context.coordinator.lastSyncPulse {
            context.coordinator.lastSyncPulse = syncPulse
            context.coordinator.triggerSilentWifiSync()
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onOpenWifiConfig: () -> Void
        let onThemeChange: (String, Bool) -> Void
        weak var webView: WKWebView?
        var wifiServerUrl: String = ""
        var lastSyncPulse: Int = 0
        private var pathMonitor: NWPathMonitor?
        private var syncTimer: Timer?
        private var isSyncing = false

        private lazy var urlSession: URLSession = {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 3.5
            cfg.timeoutIntervalForResource = 12.0
            return URLSession(configuration: cfg)
        }()

        init(onOpenWifiConfig: @escaping () -> Void, onThemeChange: @escaping (String, Bool) -> Void) {
            self.onOpenWifiConfig = onOpenWifiConfig
            self.onThemeChange = onThemeChange
        }

        deinit {
            pathMonitor?.cancel()
            syncTimer?.invalidate()
        }

        private var docsDir: URL {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        private var metaFileURL: URL { docsDir.appendingPathComponent("books_meta.json") }
        private var libraryFileURL: URL { docsDir.appendingPathComponent("books_library.json") }

        func startNetworkMonitor() {
            pathMonitor?.cancel()
            let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
            monitor.pathUpdateHandler = { [weak self] path in
                if path.status == .satisfied {
                    self?.triggerSilentWifiSync()
                } else {
                    self?.notifyWifiStatus(connected: false)
                }
            }
            monitor.start(queue: DispatchQueue.global(qos: .utility))
            pathMonitor = monitor

            DispatchQueue.main.async { [weak self] in
                self?.syncTimer?.invalidate()
                self?.syncTimer = Timer.scheduledTimer(withTimeInterval: 12.0, repeats: true) { [weak self] _ in
                    self?.triggerSilentWifiSync()
                }
            }
        }

        private func notifyWifiStatus(connected: Bool) {
            let js = "window.__onNativeWifiStatus && window.__onNativeWifiStatus({connected: \(connected ? "true" : "false")});"
            DispatchQueue.main.async {
                self.webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        private func hydrateFromDisk() {
            DispatchQueue.global(qos: .userInitiated).async {
                var merged: [String: Any] = [:]
                if let mData = try? Data(contentsOf: self.metaFileURL),
                   let mObj = try? JSONSerialization.jsonObject(with: mData) as? [String: Any] {
                    merged = mObj
                }
                if let lData = try? Data(contentsOf: self.libraryFileURL),
                   let lObj = try? JSONSerialization.jsonObject(with: lData) as? [String: Any] {
                    if let books = lObj["books"] { merged["books"] = books }
                    if let del = lObj["deletedBookIds"] { merged["deletedBookIds"] = del }
                    if let ver = lObj["libraryVersion"] { merged["libraryVersion"] = ver }
                }
                guard !merged.isEmpty,
                      let outData = try? JSONSerialization.data(withJSONObject: merged),
                      let jsonStr = String(data: outData, encoding: .utf8),
                      let wrapped = try? JSONSerialization.data(withJSONObject: [jsonStr]),
                      let arrStr = String(data: wrapped, encoding: .utf8) else { return }
                let js = "window.__hydrateNativeBooksState && window.__hydrateNativeBooksState((\(arrStr))[0]);"
                DispatchQueue.main.async {
                    self.webView?.evaluateJavaScript(js, completionHandler: nil)
                }
            }
        }

        func triggerSilentWifiSync() {
            let base = wifiServerUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !base.isEmpty, let pingURL = URL(string: "\(base)/api/ping"), !isSyncing else {
                if base.isEmpty { notifyWifiStatus(connected: false) }
                return
            }
            isSyncing = true
            urlSession.dataTask(with: pingURL) { [weak self] data, resp, err in
                guard let self = self else { return }
                guard err == nil, let http = resp as? HTTPURLResponse, http.statusCode == 200, data != nil else {
                    self.isSyncing = false
                    self.notifyWifiStatus(connected: false)
                    return
                }
                self.notifyWifiStatus(connected: true)
                self.pullRemoteState(base: base)
            }.resume()
        }

        private func pullRemoteState(base: String) {
            guard let syncURL = URL(string: "\(base)/api/sync"),
                  let booksURL = URL(string: "\(base)/api/books") else {
                isSyncing = false
                return
            }
            urlSession.dataTask(with: syncURL) { [weak self] mData, _, _ in
                guard let self = self else { return }
                let remoteMetaStr = mData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                self.urlSession.dataTask(with: booksURL) { [weak self] bData, _, _ in
                    guard let self = self else { return }
                    let remoteBooksStr = bData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    self.isSyncing = false
                    if let wrapped = try? JSONSerialization.data(withJSONObject: [remoteMetaStr, remoteBooksStr]),
                       let arrStr = String(data: wrapped, encoding: .utf8) {
                        let js = "window.__applyNativeWifiSync && window.__applyNativeWifiSync((\(arrStr))[0], (\(arrStr))[1]);"
                        DispatchQueue.main.async {
                            self.webView?.evaluateJavaScript(js, completionHandler: nil)
                        }
                    }
                }.resume()
            }.resume()
        }

        private func pushToWifi(path: String, jsonData: Data) {
            let base = wifiServerUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !base.isEmpty, let url = URL(string: "\(base)\(path)") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = jsonData
            urlSession.dataTask(with: req) { [weak self] _, resp, err in
                if err == nil, let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    self?.notifyWifiStatus(connected: true)
                }
            }.resume()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            hydrateFromDisk()
            triggerSilentWifiSync()
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            if let localHtml = Bundle.main.url(forResource: "index", withExtension: "html") {
                webView.loadFileURL(localHtml, allowingReadAccessTo: localHtml.deletingLastPathComponent())
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "booksBridge", let cmd = message.body as? String {
                if cmd == "openWifiConfig" {
                    DispatchQueue.main.async { self.onOpenWifiConfig() }
                } else if cmd == "requestSavedState" {
                    hydrateFromDisk()
                } else if cmd == "triggerWifiSync" {
                    triggerSilentWifiSync()
                }
            } else if message.name == "booksSaveMeta", let raw = message.body as? String,
                      let data = raw.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let meta = obj["meta"],
                      let metaData = try? JSONSerialization.data(withJSONObject: meta) {
                let skipPush = (obj["skipWifiPush"] as? Bool) ?? false
                DispatchQueue.global(qos: .utility).async {
                    try? metaData.write(to: self.metaFileURL, options: .atomic)
                    if !skipPush { self.pushToWifi(path: "/api/sync", jsonData: metaData) }
                }
            } else if message.name == "booksSaveLibrary", let raw = message.body as? String,
                      let data = raw.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let libData = try? JSONSerialization.data(withJSONObject: obj) {
                let skipPush = (obj["skipWifiPush"] as? Bool) ?? false
                DispatchQueue.global(qos: .utility).async {
                    try? libData.write(to: self.libraryFileURL, options: .atomic)
                    if !skipPush { self.pushToWifi(path: "/api/books", jsonData: libData) }
                }
            } else if message.name == "booksTheme", let dict = message.body as? [String: Any],
                      let bg = dict["bg"] as? String, let dark = dict["dark"] as? Bool {
                DispatchQueue.main.async {
                    self.onThemeChange(bg, dark)
                }
            }
        }
    }
}
