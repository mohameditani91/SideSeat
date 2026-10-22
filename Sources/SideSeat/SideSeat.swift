import UIKit

/// Lets a support agent see, and with the user's consent control, this app from a browser.
public final class SideSeat {

    public struct Configuration {
        /// The relay's device endpoint, for example `ws://localhost:8080/device`. Add auth headers or query items here.
        public var request: URLRequest
        /// Replaces the WebSocket transport, for example to run over your own backend.
        public var transport: SideSeatTransport?
        public var allowsControl = true
        public var framesPerSecond: Double = 2
        public var scale: CGFloat = 1
        public var jpegQuality: CGFloat = 0.7
        /// Frame rate halves while a capture takes longer than this on the main thread.
        public var mainThreadBudget: TimeInterval = 0.05
        /// Returns true for views to paint black. Secure text fields and `isSideSeatMasked` views are always masked.
        public var maskRule: ((UIView) -> Bool)?
        /// Sees every agent input first. Return a result to handle or block it, or nil to let SideSeat perform it.
        public var inputInterceptor: ((RemoteInput) -> InputResult?)?
        /// Replaces the built-in consent card. Call the completion with the granted mode, or nil to deny.
        public var consentHandler: ((Agent, @escaping (SessionMode?) -> Void) -> Void)?
        public var strings = SideSeatStrings()
        public var tint: UIColor = .systemBlue

        public init(request: URLRequest) {
            self.request = request
        }

        public init(relay url: URL) {
            self.init(request: URLRequest(url: url))
        }
    }

    public static let shared = SideSeat()

    public var onStateChange: ((SessionState) -> Void)?
    public var state: SessionState? { session?.state }
    public var isRunning: Bool { session != nil }

    private var session: Session?
    private var streamer: Streamer?
    private var overlay: OverlayWindow?

    public init() {}

    public func start(in scene: UIWindowScene, configuration: Configuration) {
        guard session == nil else { return }

        let session = Session(transport: configuration.transport ?? WebSocketTransport(request: configuration.request), allowsControl: configuration.allowsControl)
        let dispatcher = InputDispatcher(windows: { [weak scene] in scene?.windows ?? [] }, bounds: { [weak scene] in scene?.coordinateSpace.bounds ?? .zero })
        session.perform = { input in configuration.inputInterceptor?(input) ?? dispatcher.perform(input) }

        let controller = OverlayViewController(strings: configuration.strings, tint: configuration.tint, allowsControl: configuration.allowsControl, showsConsent: configuration.consentHandler == nil)
        controller.onCancel = { [weak self] in self?.end() }
        controller.onEnd = { [weak self] in self?.end() }
        controller.onAllow = { [weak session] in session?.grant($0) }
        controller.onDeny = { [weak session] in session?.deny() }
        controller.onViewOnly = { [weak session] in session?.switchToViewOnly() }

        let window = OverlayWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = controller
        window.isHidden = false

        let streamer = Streamer(scene: scene, configuration: configuration, session: session)
        session.onStateChange = { [weak self, weak session, weak controller, weak streamer] state in
            controller?.render(state)
            if case .active = state { streamer?.restart() }
            if case .awaitingConsent(_, let agent) = state, let ask = configuration.consentHandler {
                ask(agent) { mode in
                    DispatchQueue.main.async {
                        if let mode { session?.grant(mode) } else { session?.deny() }
                    }
                }
            }
            if case .ended = state { self?.tearDown() }
            self?.onStateChange?(state)
        }

        self.session = session
        self.streamer = streamer
        self.overlay = window
        controller.render(.connecting)
        streamer.start()
        session.start()
    }

    public func end() {
        session?.end()
    }

    private func tearDown() {
        streamer?.stop()
        overlay?.isHidden = true
        overlay = nil
        streamer = nil
        session = nil
    }
}
