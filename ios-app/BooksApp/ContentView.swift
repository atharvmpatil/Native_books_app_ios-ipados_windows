import SwiftUI
import WebKit

struct ContentView: View {
    @AppStorage("windowsWifiUrl") private var windowsWifiUrl: String = ""
    @State private var showWifiPrompt = false
    @State private var urlDraft = ""

    var body: some View {
        ZStack(alignment: .topTrailing) {
            BooksWebView(remoteUrl: windowsWifiUrl)
                .ignoresSafeArea(edges: .bottom)

            Button {
                urlDraft = windowsWifiUrl
                showWifiPrompt = true
            } label: {
                Image(systemName: windowsWifiUrl.isEmpty ? "wifi.slash" : "wifi")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.top, 10)
            .padding(.trailing, 14)
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

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.bounces = false
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
}
