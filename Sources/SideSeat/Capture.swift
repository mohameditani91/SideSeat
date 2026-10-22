import UIKit

enum WindowSelection {

    private static let uiKitBundle = Bundle(for: UIWindow.self)

    static func capturable(_ windows: [UIWindow]) -> [UIWindow] {
        windows.enumerated()
            .filter { !$0.element.isHidden && $0.element.alpha > 0.01 && isAppWindow($0.element) }
            .sorted { ($0.element.windowLevel.rawValue, $0.offset) < ($1.element.windowLevel.rawValue, $1.offset) }
            .map(\.element)
    }

    static func forInput(_ windows: [UIWindow]) -> [UIWindow] {
        capturable(windows).filter(\.isUserInteractionEnabled).reversed()
    }

    private static func isAppWindow(_ window: UIWindow) -> Bool {
        if window is OverlayWindow { return false }
        let windowClass = type(of: window)
        return windowClass == UIWindow.self || Bundle(for: windowClass) != uiKitBundle
    }
}

enum Compositor {

    static func capture(_ scene: UIWindowScene, scale: CGFloat, maskRule: ((UIView) -> Bool)?) -> CGImage? {
        let space = scene.coordinateSpace
        let bounds = space.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
            UIColor.black.setFill()
            context.fill(bounds)
            for window in WindowSelection.capturable(scene.windows) {
                window.drawHierarchy(in: window.convert(window.bounds, to: space), afterScreenUpdates: false)
                for rect in MaskCollector.rects(in: window, rule: maskRule) {
                    context.fill(window.convert(rect, to: space))
                }
            }
        }.cgImage
    }
}

struct FrameRatePolicy: Equatable {

    static let floor = 0.5
    static let slowFramesToSlowDown = 3
    static let fastFramesToSpeedUp = 10

    private(set) var fps: Double
    private let maxFps: Double
    private let budget: TimeInterval
    private var slowStreak = 0
    private var fastStreak = 0

    init(maxFps: Double, budget: TimeInterval) {
        self.fps = maxFps
        self.maxFps = maxFps
        self.budget = budget
    }

    mutating func record(_ duration: TimeInterval) -> Bool {
        let previous = fps
        if duration > budget {
            fastStreak = 0
            slowStreak += 1
            if slowStreak >= Self.slowFramesToSlowDown {
                slowStreak = 0
                fps = max(fps / 2, min(Self.floor, maxFps))
            }
        } else if duration < budget * 0.6 {
            slowStreak = 0
            fastStreak += 1
            if fastStreak >= Self.fastFramesToSpeedUp {
                fastStreak = 0
                fps = min(fps * 2, maxFps)
            }
        } else {
            slowStreak = 0
            fastStreak = 0
        }
        return fps != previous
    }
}

final class Streamer {

    private weak var scene: UIWindowScene?
    private let configuration: SideSeat.Configuration
    private let session: Session
    private let encodeQueue = DispatchQueue(label: "SideSeat.encode", qos: .userInitiated)
    private var policy: FrameRatePolicy
    private var timer: Timer?
    private var inFlight = false
    private var lastFrame: Data?
    private var lastSize: CGSize?

    init(scene: UIWindowScene, configuration: SideSeat.Configuration, session: Session) {
        self.scene = scene
        self.configuration = configuration
        self.session = session
        self.policy = FrameRatePolicy(maxFps: configuration.framesPerSecond, budget: configuration.mainThreadBudget)
    }

    func start() {
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func restart() {
        lastFrame = nil
        lastSize = nil
    }

    private func schedule() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1 / policy.fps, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard session.isStreaming, !inFlight, let scene else { return }
        let size = scene.coordinateSpace.bounds.size
        if size != lastSize {
            lastSize = size
            lastFrame = nil
            session.sendScreen(width: size.width, height: size.height)
        }

        let started = CACurrentMediaTime()
        guard let image = Compositor.capture(scene, scale: configuration.scale, maskRule: configuration.maskRule) else { return }
        if policy.record(CACurrentMediaTime() - started) { schedule() }

        inFlight = true
        let quality = configuration.jpegQuality
        let previous = lastFrame
        encodeQueue.async { [weak self] in
            let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: quality)
            DispatchQueue.main.async {
                guard let self else { return }
                guard let jpeg, jpeg != previous, self.session.isStreaming else {
                    self.inFlight = false
                    return
                }
                self.lastFrame = jpeg
                self.session.sendFrame(jpeg) { [weak self] in self?.inFlight = false }
            }
        }
    }
}
