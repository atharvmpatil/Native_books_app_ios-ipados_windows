import SwiftUI
import WebKit

struct ContentView: View {
    @AppStorage("windowsWifiUrl") private var windowsWifiUrl: String = ""
    @State private var showWifiPrompt = false
    @State private var urlDraft = ""

    var body: some View {
        ZStack {
            // Matching native background behind the Dynamic Island & status bar (zero black bars!)
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea(.all)

            // WebView stays cleanly BELOW the Dynamic Island / status bar, extending to bottom edge
            BooksWebView(remoteUrl: windowsWifiUrl) {
                urlDraft = windowsWifiUrl
                showWifiPrompt = true
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
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

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenWifiConfig: onOpenWifiConfig)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "booksBridge")
        contentController.add(context.coordinator, name: "booksSave")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = UIColor.systemGroupedBackground
        webView.scrollView.backgroundColor = UIColor.systemGroupedBackground
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
        weak var webView: WKWebView?

        init(onOpenWifiConfig: @escaping () -> Void) {
            self.onOpenWifiConfig = onOpenWifiConfig
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
            }
        }
    }
}
