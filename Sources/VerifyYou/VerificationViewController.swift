import UIKit
import WebKit

/// Full-screen host for app-fe's native page. The flow and its result come
/// from the web SDK running inside; this controller owns
/// only what a browser would: the camera prompt, the message channel, a close
/// button, and getting the screen off when it settles. The button stays up the
/// whole run because the flow shows no close control inside native.html.
final class VerificationViewController: UIViewController {
    private let url: URL
    private let finish: (BridgeMessage) -> Void
    private var settled = false
    private var ready = false
    private var webView: WKWebView!
    private let closeButton = UIButton(type: .system)

    /// How long a close request waits for the page's own `vy:close` before
    /// closing anyway (a hung page must never trap the person).
    private static let closeGrace: TimeInterval = 1.5

    init(url: URL, finish: @escaping (BridgeMessage) -> Void) {
        self.url = url
        self.finish = finish
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Locks to portrait regardless of the host app's own orientation mask --
    // effective because this is presented .fullScreen (see init above); a
    // face-liveness capture UI in landscape is a UX correctness issue, not a
    // style preference, so the SDK owns this rather than leaving it to the
    // integrator.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var shouldAutorotate: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(WeakMessageHandler(self), name: Bridge.handlerName)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 16.4, *) {
            webView.isInspectable = VerifyYou.webInspectorEnabled
        }
        view.addSubview(webView)
        // Inside the safe area: safe-area insets don't reach into the web SDK's
        // iframe, so the flow can't pad around the notch itself.
        NSLayoutConstraint.activate([
            // The flow starts below the close button's band, so the button never covers the flow's header.
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 52),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.accessibilityLabel = "Close"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),
        ])

        webView.load(URLRequest(url: url))
    }

    // A dismissal the host started itself (not this controller): the run is over.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed, !settled {
            settled = true
            finish(.close)
        }
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: Bridge.handlerName)
        // Freed without settling (UIKit dropped the present()): end the run, or the
        // SDK reports "already in progress" until the app restarts.
        if !settled { finish(.close) }
    }

    @objc private func closeTapped() {
        requestClose()
    }

    /// Before the page is up there is nothing to ask, so close directly. After,
    /// ask the web SDK (so it tears down the way it does on the web and answers
    /// `vy:close`), with a grace timeout in case the page is hung.
    func requestClose() {
        guard !settled else { return }
        guard ready else {
            settle(.close)
            return
        }
        let fn = Bridge.closeFunction
        webView.evaluateJavaScript("(window.\(fn) && window.\(fn)(), true)") { [weak self] _, error in
            if error != nil { self?.settle(.close) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeGrace) { [weak self] in
            self?.settle(.close)
        }
    }

    /// The handle's start watchdog fired: dismiss, then report the error.
    func fail(_ message: String) {
        settle(.error(message))
    }

    fileprivate func receive(_ message: BridgeMessage) {
        switch message {
        case .ready:
            guard !settled, !ready else { return }
            ready = true
            finish(.ready)
        case .complete, .close, .error:
            settle(message)
        }
    }

    private func settle(_ outcome: BridgeMessage) {
        guard !settled else { return }
        settled = true
        // Report only once the screen is gone: a retry from the callback must find
        // the presenter free, or UIKit drops its present().
        let report = { [finish] in finish(outcome) }
        // An offline load can fail while the screen is still presenting, and
        // UIKit drops a dismissal requested mid-transition.
        if let transition = transitionCoordinator {
            transition.animate(alongsideTransition: nil) { _ in self.dismissThen(report) }
        } else {
            dismissThen(report)
        }
    }

    private func dismissThen(_ report: @escaping () -> Void) {
        // Never presented, so there is no dismissal to wait for.
        if presentingViewController == nil { report() } else { dismiss(animated: true, completion: report) }
    }

    /// A navigation that was superseded or stopped by policy, not a failure.
    private static func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
            || (nsError.domain == "WebKitErrorDomain" && nsError.code == 102)
    }
}

extension VerificationViewController: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame,
            isSameOrigin(scheme: origin.protocol, host: origin.host, port: origin.port, as: url),
            let parsed = parseBridgeMessage(message.body)
        else { return }
        receive(parsed)
    }
}

extension VerificationViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // The host page never navigates itself; anything leaving its origin at
        // the top level is not part of the flow.
        if navigationAction.targetFrame?.isMainFrame == true,
            let target = navigationAction.request.url,
            !isSameOrigin(scheme: target.scheme, host: target.host, port: target.port, as: url)
        {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.isForMainFrame,
            let http = navigationResponse.response as? HTTPURLResponse, http.statusCode >= 400
        {
            decisionHandler(.cancel)
            settle(.error("the verification page returned an error"))
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) {
        guard !Self.isCancellation(error) else { return }
        settle(.error("the verification page failed to load"))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !Self.isCancellation(error) else { return }
        settle(.error("the verification page failed to load"))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        settle(.error("the verification page crashed"))
    }
}

extension VerificationViewController: WKUIDelegate {
    // Liveness needs the camera inside the web SDK's iframe -- the native
    // equivalent of its iframe.allow="camera". The frame is same-origin with
    // the host page, so only that origin is granted, and only for video: an audio
    // request would crash an app without NSMicrophoneUsageDescription. The
    // consuming app still needs NSCameraUsageDescription; the OS prompt sits
    // above this grant.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        let allowed =
            type == .camera
            && isSameOrigin(scheme: origin.protocol, host: origin.host, port: origin.port, as: url)
        decisionHandler(allowed ? .grant : .deny)
    }
}

/// WKUserContentController retains its handlers; this keeps it from retaining
/// the controller (and with it the WebView) past dismissal.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: VerificationViewController?

    init(_ target: VerificationViewController) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
