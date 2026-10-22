import UIKit
import SideSeat

enum Support {

    static let defaultRelay = "ws://localhost:8080/device"

    static var relay: String {
        get { UserDefaults.standard.string(forKey: "SideSeatRelay") ?? defaultRelay }
        set { UserDefaults.standard.set(newValue, forKey: "SideSeatRelay") }
    }

    static func start(in scene: UIWindowScene) {
        guard let url = URL(string: relay) else { return }
        var configuration = SideSeat.Configuration(relay: url)
        configuration.tint = .systemIndigo
        configuration.maskRule = MaskRules.screens([CardDetailsViewController.self])
        if let mode = UserDefaults.standard.string(forKey: "SideSeatAutoConsent").flatMap(SessionMode.init(rawValue:)) {
            configuration.consentHandler = { _, decide in decide(mode) }
        }
        SideSeat.shared.start(in: scene, configuration: configuration)
    }

    static func startIfRequested(in scene: UIWindowScene) {
        guard UserDefaults.standard.bool(forKey: "SideSeatAutoStart") else { return }
        DispatchQueue.main.async { start(in: scene) }
    }
}
