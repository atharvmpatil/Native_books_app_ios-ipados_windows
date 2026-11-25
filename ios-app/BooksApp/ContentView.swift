import SwiftUI
import WebKit

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
    @State private var showWifiPrompt = false
    @State private var urlDraft = ""
    @State private var themeBgHex = "#f5f5f7"
    @State private var isDarkTheme = false

    var body: some View {
        ZStack {
            // Dynamically matches active theme behind Dynamic Island & clock (pure black in Focus, warm cream in Paper!)
            Color(hex: themeBgHex)
                .ignoresSafeArea(.all)

            // WebView stays cleanly BELOW the Dynamic Island / status bar, extending to bottom edge
            BooksWebView(
                remoteUrl: windowsWifiUrl,
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
        .alert("Connect to Windows PC Wi-Fi Sync", isPresented: $showWifiPrompt) {
            TextField("http://192.168.1.42:8765", text: $urlDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Connect") {
                windowsWifiUrl = urlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            Button("Use Offline Copy", role: .destructive) {
                windowsWifiUrl = ""
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the Wi-Fi link shown by AppleBooksWindows.exe on your Windows PC.")
        }
    }
}

struct BooksWebView: UIViewRepresentable {
    let remoteUrl: String
    let onOpenWifiConfig: () -> Void
    let onThemeChange: (String, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenWifiConfig: onOpenWifiConfig, onThemeChange: onThemeChange)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "booksBridge")
        contentController.add(context.coordinator, name: "booksSave")
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
        loadTarget(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        loadTarget(in: webView)
    }

    private func loadTarget(in webView: WKWebView) {
        if let url = URL(string: remoteUrl), !remoteUrl.isEmpty, url.scheme?.hasPrefix("http") == true {
            if webView.url?.absoluteString != url.absoluteString {
                webView.load(URLRequest(url: url))
            }
        } else if let localHtml = Bundle.main.url(forResource: "index", withExtension: "html") {
            if webView.url != localHtml {
                webView.loadFileURL(localHtml, allowingReadAccessTo: localHtml.deletingLastPathComponent())
            }
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onOpenWifiConfig: () -> Void
        let onThemeChange: (String, Bool) -> Void
        weak var webView: WKWebView?

        init(onOpenWifiConfig: @escaping () -> Void, onThemeChange: @escaping (String, Bool) -> Void) {
            self.onOpenWifiConfig = onOpenWifiConfig
            self.onThemeChange = onThemeChange
        }

        private var stateFileURL: URL {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return docs.appendingPathComponent("books_state.json")
        }

        private func saveStateToDisk(_ json: String) {
            DispatchQueue.global(qos: .utility).async {
                try? json.data(using: .utf8)?.write(to: self.stateFileURL, options: .atomic)
            }
        }

        private func pushSavedStateToWebView() {
            guard let data = try? Data(contentsOf: stateFileURL),
                  let jsonStr = String(data: data, encoding: .utf8),
                  let encoded = try? JSONSerialization.data(withJSONObject: [jsonStr]),
                  let arrStr = String(data: encoded, encoding: .utf8) else { return }
            let js = "window.__hydrateNativeBooksState && window.__hydrateNativeBooksState((\(arrStr))[0]);"
            DispatchQueue.main.async {
                self.webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pushSavedStateToWebView()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "booksBridge", let cmd = message.body as? String {
                if cmd == "openWifiConfig" {
                    DispatchQueue.main.async { self.onOpenWifiConfig() }
                } else if cmd == "requestSavedState" {
                    pushSavedStateToWebView()
                }
            } else if message.name == "booksSave", let json = message.body as? String {
                saveStateToDisk(json)
            } else if message.name == "booksTheme", let dict = message.body as? [String: Any],
                      let bg = dict["bg"] as? String, let dark = dict["dark"] as? Bool {
                DispatchQueue.main.async {
                    self.onThemeChange(bg, dark)
                }
            }
        }
    }
}
