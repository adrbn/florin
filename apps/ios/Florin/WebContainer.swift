import SwiftUI
import WebKit

/// Full-bleed WKWebView hosting the Florin v2 surface.
struct WebContainer: UIViewRepresentable {
    let url: URL
    let onRequestSettings: () -> Void
    /// Called instead of navigating when the page links into another tab's
    /// territory. The host switches the tab bar and loads it there.
    var onCrossTab: ((TabRoute, String) -> Void)?
    /// Called instead of navigating for a Florin path no tab owns (Plan,
    /// Review, Categories, Tools) so the host can push it on the current stack.
    var onPush: ((String) -> Void)?
    /// Which tab this web view belongs to; nil for a pushed screen, which owns
    /// no territory and therefore never triggers a switch.
    var homeTab: TabRoute?
    /// Set while a page is in flight, so the host can hold a placeholder
    /// instead of a white rectangle.
    var isLoading: Binding<Bool>?
    /// Which appearance the page should render in — the app's, not the device's.
    var appearance: ColorScheme = .dark
    /// Vertical scroll offset, so the shell's tab bar can collapse on a web tab
    /// exactly as it does on a native one.
    var onScroll: ((CGFloat) -> Void)?
    /// A sheet opened or closed inside the page. The shell's bar floats above
    /// this web view, so it has to move aside or it covers the sheet's actions.
    var onSheet: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, onRequestSettings: onRequestSettings)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        /*
         * Pin the viewport.
         *
         * The page ships a normal, zoomable viewport because in a browser that
         * is the accessible thing to do. Inside the app it is not: this is a
         * fixed-width phone composition with a floating tab bar, and pinching
         * it just breaks the layout. Injecting the constraint here keeps the
         * web page honest for browser users and makes the app behave like an
         * app.
         */
        let pinViewport = """
        (function () {
          var tag = document.querySelector('meta[name=viewport]')
          if (!tag) { tag = document.createElement('meta'); tag.name = 'viewport'; document.head.appendChild(tag) }
          tag.setAttribute('content',
            'width=device-width, initial-scale=1, maximum-scale=1, minimum-scale=1, user-scalable=no, viewport-fit=cover')
        })();
        """

        /*
         * The page themes itself with next-themes, which follows the *system*
         * appearance. Inside the app the appearance is the app's setting, so a
         * dark app on a light phone would show dark native screens and white
         * web ones. Writing the class and the stored preference before first
         * paint keeps the two halves the same colour.
         */
        let forceScheme = """
        (function () {
          var dark = \(appearance == .dark ? "true" : "false");
          try { localStorage.setItem('theme', dark ? 'dark' : 'light') } catch (e) {}
          document.documentElement.classList.toggle('dark', dark);
          document.documentElement.style.colorScheme = dark ? 'dark' : 'light';
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: pinViewport, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        // At documentStart so the page never paints in the wrong scheme first.
        config.userContentController.addUserScript(
            WKUserScript(source: forceScheme, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        config.userContentController.add(context.coordinator, name: "florin")
        // The default (persistent) store keeps the NextAuth session cookie, so
        // the user signs in once rather than on every cold launch.
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        /*
         * The server keys chromeless mode off this suffix: when Florin sees
         * `FlorinApp/` in the user agent it drops its own floating tab bar and
         * profile button, because the native shell already draws them. It has
         * to be set on the configuration before the web view is created —
         * WKWebView copies the configuration on init.
         */
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        config.applicationNameForUserAgent = "FlorinApp/\(version)"

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Let the page paint the notch and the home-indicator strip itself —
        // the v2 CSS already reserves them with env(safe-area-inset-*), and an
        // opaque web view would draw an off-colour band over both.
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // The viewport meta above stops double-tap zoom; this stops the pinch
        // gesture, which WKWebView honours independently of the meta tag.
        webView.scrollView.bouncesZoom = false
        webView.scrollView.minimumZoomScale = 1
        webView.scrollView.maximumZoomScale = 1
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false

        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.reload), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        context.coordinator.attach(webView)

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onRequestSettings = onRequestSettings
        context.coordinator.onCrossTab = onCrossTab
        context.coordinator.onPush = onPush
        context.coordinator.homeTab = homeTab
        context.coordinator.isLoading = isLoading
        context.coordinator.onScroll = onScroll
        context.coordinator.onSheet = onSheet
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let url: URL
        var onRequestSettings: () -> Void
        var onCrossTab: ((TabRoute, String) -> Void)?
        var onPush: ((String) -> Void)?
        var homeTab: TabRoute?
        var isLoading: Binding<Bool>?
        var onScroll: ((CGFloat) -> Void)?
        var onSheet: ((Bool) -> Void)?
        private var offsetObservation: NSKeyValueObservation?
        private weak var webView: WKWebView?
        private var errorView: UIView?

        init(url: URL, onRequestSettings: @escaping () -> Void) {
            self.url = url
            self.onRequestSettings = onRequestSettings
        }

        func userContentController(
            _ controller: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any],
                  body["type"] as? String == "sheet",
                  let open = body["open"] as? Bool
            else { return }
            Task { @MainActor in self.onSheet?(open) }
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
            // KVO rather than becoming the scroll view's delegate: WKWebView
            // uses that delegate itself, and stealing it breaks its own
            // gesture handling.
            offsetObservation = webView.scrollView.observe(\.contentOffset, options: [.new]) {
                [weak self] scrollView, _ in
                let y = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
                Task { @MainActor in self?.onScroll?(y) }
            }
        }

        deinit { offsetObservation?.invalidate() }

        @objc func reload() {
            hideError()
            webView?.load(URLRequest(url: url))
        }

        @objc func openSettings() { onRequestSettings() }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading?.wrappedValue = true
            // The new page has no sheet yet; without this the bar would stay
            // hidden after navigating away from one.
            onSheet?(false)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            isLoading?.wrappedValue = false
            hideError()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            showError(on: webView, error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            showError(on: webView, error)
        }

        /// Keep Florin's own pages in the app; hand everything else to Safari.
        ///
        /// A bank's PSD2 consent page must run in a real browser — it
        /// fingerprints the user agent, and some issuers refuse an embedded web
        /// view outright — so bouncing off-host navigations out is a
        /// correctness requirement, not a nicety.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let target = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let sameHost = target.host == url.host && target.port == url.port
            let webScheme = target.scheme == "http" || target.scheme == "https"

            if sameHost {
                /*
                 * A link out of this tab's territory is handed to the shell
                 * rather than followed here. Following it would leave the page
                 * showing Activity while the tab bar still says Analysis — the
                 * user would have to swipe back to find where they are, which
                 * is exactly the disorientation a native shell is supposed to
                 * prevent.
                 */
                let path = target.path
                let destination = TabRoute.owning(path: path)
                let full = path + (target.query.map { "?\($0)" } ?? "")

                if navigationAction.navigationType == .linkActivated,
                   let homeTab,
                   destination != homeTab {
                    decisionHandler(.cancel)
                    if let destination {
                        onCrossTab?(destination, full)
                    } else {
                        onPush?(full)
                    }
                    return
                }
                decisionHandler(.allow)
                return
            }
            if !webScheme {
                decisionHandler(.allow)
                return
            }
            if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
                decisionHandler(.cancel)
                UIApplication.shared.open(target)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // target="_blank" has no window to open into here.
            if let target = navigationAction.request.url { UIApplication.shared.open(target) }
            return nil
        }

        // MARK: - Unreachable-server state

        private func showError(on webView: WKWebView, _ error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
            isLoading?.wrappedValue = false
            // A cancelled navigation is what every redirect looks like; showing
            // an error for it would flash a failure on a perfectly good load.
            if (error as NSError).code == NSURLErrorCancelled { return }
            guard errorView == nil, let host = webView.superview ?? webView as UIView? else { return }

            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.backgroundColor = .clear

            // This screen is what the app shows when the server is out of
            // reach — which is exactly when the feed that carries the
            // translations cannot arrive either, so it speaks the handset's
            // language rather than waiting for one that will never come.
            let t = Strings.device

            let title = UILabel()
            title.text = t("v2.common.unreachableTitle", "Florin est injoignable")
            title.font = .systemFont(ofSize: 19, weight: .semibold)
            title.textAlignment = .center

            let detail = UILabel()
            detail.text = t("v2.common.unreachable", "{host} ne répond pas.", ["host": url.host ?? ""])
                + "\n"
                + t("v2.common.unreachableHint", "Vérifie que le serveur tourne et que tu es sur le bon réseau.")
            detail.font = .systemFont(ofSize: 14)
            detail.textColor = .secondaryLabel
            detail.numberOfLines = 0
            detail.textAlignment = .center

            let retry = UIButton(configuration: .filled())
            retry.setTitle(t("v2.common.retry", "Réessayer"), for: .normal)
            retry.addTarget(self, action: #selector(reload), for: .touchUpInside)

            let settings = UIButton(configuration: .plain())
            settings.setTitle(t("v2.setup.changeHost", "Changer l'adresse"), for: .normal)
            settings.addTarget(self, action: #selector(openSettings), for: .touchUpInside)

            let stack = UIStackView(arrangedSubviews: [title, detail, retry, settings])
            stack.axis = .vertical
            stack.spacing = 12
            stack.alignment = .center
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.setCustomSpacing(20, after: detail)

            container.addSubview(stack)
            host.addSubview(container)

            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                container.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                container.topAnchor.constraint(equalTo: host.topAnchor),
                container.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 32),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -32),
            ])
            errorView = container
        }

        private func hideError() {
            errorView?.removeFromSuperview()
            errorView = nil
        }
    }
}
