import SwiftUI
import WebKit

struct ContentView: View {
    @AppStorage("windowsWifiUrl") private var windowsWifiUrl: String = ""
    @State private var showWifiPrompt = false
    @State private var urlDraft = ""

    var body: some View {
        BooksWebView(remoteUrl: windowsWifiUrl) {
            urlDraft = windowsWifiUrl
            showWifiPrompt = true
        }
        .ignoresSafeArea(.all)
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

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = UIColor.systemGroupedBackground
        webView.scrollView.backgroundColor = UIColor.systemGroupedBackground
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

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onOpenWifiConfig: () -> Void
        init(onOpenWifiConfig: @escaping () -> Void) {
            self.onOpenWifiConfig = onOpenWifiConfig
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "booksBridge", (message.body as? String) == "openWifiConfig" {
                DispatchQueue.main.async {
                    self.onOpenWifiConfig()
                }
            }
        }
    }
}
