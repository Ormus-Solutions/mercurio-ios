import SwiftUI
import WebKit

/// One page from Attach Links, shown inside that list.
///
/// A loopback address is reached through an SSH tunnel to the computer.
/// Any other address is loaded as written. The person chooses which,
/// because the app does not decide from the host name.
struct DevPreviewPage: View {
    var hostID: Host.ID?
    var console: ConsoleStore?
    let page: URL

    @State private var forwarder: DevPreviewForwarder?
    @State private var forwardError: String?
    @State private var pageURL: URL?
    @State private var reloadID = 0
    @State private var attempt = 0

    private var title: String {
        DevPreview.target(from: page) == nil ? (page.host ?? "Page") : "localhost"
    }

    var body: some View {
        Group {
            if let forwardError {
                VStack(spacing: 16) {
                    message(forwardError)
                    Button("Try Again") { attempt += 1 }
                        .buttonStyle(.bordered)
                }
            } else if let pageURL {
                DevPreviewWebView(url: pageURL, reloadID: reloadID)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(OrmusPalette.deep)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if pageURL != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Reload", systemImage: "arrow.clockwise") {
                        reloadID += 1
                    }
                }
            }
        }
        .task(id: attempt) { await load() }
        .onDisappear { forwarder?.stop() }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(OrmusPalette.ink)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity)
    }

    private func load() async {
        forwardError = nil
        if let target = DevPreview.target(from: page) {
            await openLocal(target)
        } else {
            pageURL = page
        }
    }

    /// The simulator shares the computer's loopback. A phone tunnels.
    private func openLocal(_ target: DevPreview.Target) async {
        #if targetEnvironment(simulator)
        guard let direct = URL(string: "http://127.0.0.1:\(target.port)\(target.path)") else { return }
        pageURL = direct
        #else
        guard let hostID, let console else {
            forwardError = "Mercurio is not connected to that computer."
            return
        }
        do {
            forwarder?.stop()
            let started = try await console.startDevPreview(
                host: target.host, port: target.port, on: hostID)
            guard !Task.isCancelled else {
                started.stop()
                return
            }
            forwarder = started
            pageURL = URL(string: "http://127.0.0.1:\(started.localPort)\(target.path)")
        } catch {
            guard !Task.isCancelled else { return }
            forwardError = DevPreview.message(for: error)
        }
        #endif
    }
}

/// Pins the page to the glass. An in-app window often reports a height much
/// taller than the screen, so a site that sizes its first screen to that
/// height parks the words below the fold. A fast flick is the only way to
/// catch them before smooth scroll pulls back to the empty top.
private struct DevPreviewWebView: UIViewControllerRepresentable {
    let url: URL
    let reloadID: Int

    func makeUIViewController(context: Context) -> PreviewPageController {
        let controller = PreviewPageController()
        controller.load(url, reloadID: reloadID)
        return controller
    }

    func updateUIViewController(_ controller: PreviewPageController, context: Context) {
        controller.load(url, reloadID: reloadID)
    }
}

private final class PreviewPageController: UIViewController, WKNavigationDelegate {
    private let webView: WKWebView
    private var loadedURL: URL?
    private var loadedID = -1

    /// Runs before the site's own scripts, so its window measurement sees
    /// the real glass instead of a tall phantom viewport.
    private static let viewportScript = """
    (function () {
      function height() {
        var box = window.visualViewport;
        if (box && box.height > 50) return Math.round(box.height);
        return Math.round(window.screen.height / (window.devicePixelRatio || 1));
      }
      try {
        Object.defineProperty(window, "innerHeight", {
          configurable: true,
          get: height
        });
      } catch (e) {}
      function fit() {
        var px = height() + "px";
        var sheet = document.getElementById("mercurio-preview-fit");
        if (!sheet) {
          sheet = document.createElement("style");
          sheet.id = "mercurio-preview-fit";
          document.documentElement.appendChild(sheet);
        }
        sheet.textContent = ".min-h-screen,.h-screen{min-height:" + px + " !important;height:auto !important;}";
        var nodes = document.querySelectorAll("html, body, canvas");
        for (var i = 0; i < nodes.length; i++) {
          var node = nodes[i];
          if (node.tagName === "CANVAS") node.style.height = px;
          node.style.transform = "none";
        }
        var covers = document.querySelectorAll("[aria-hidden='true']");
        for (var j = 0; j < covers.length; j++) {
          var cover = covers[j];
          var name = String(cover.className || "");
          if (name.indexOf("z-[100]") !== -1 || name.indexOf("inset-0") !== -1 && name.indexOf("fixed") !== -1 && name.indexOf("z-") !== -1) {
            cover.style.opacity = "0";
          }
        }
        if (document.body) document.body.style.overflow = "auto";
      }
      document.addEventListener("DOMContentLoaded", fit);
      window.addEventListener("load", fit);
      setInterval(fit, 400);
    })();
    """

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.viewportScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isOpaque = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func load(_ url: URL, reloadID: Int) {
        guard loadedURL != url || loadedID != reloadID else { return }
        loadedURL = url
        loadedID = reloadID
        guard isViewLoaded, view.window != nil else { return }
        webView.load(URLRequest(url: url))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let loadedURL else { return }
        webView.load(URLRequest(url: loadedURL))
    }
}
