import UIKit

public struct SideSeatStrings {
    public var connecting = "Connecting…"
    public var codeTitle = "Support code"
    public var codeMessage = "Read this code to the support agent."
    public var consentTitle = "Allow support?"
    public var consentMessage: (String) -> String = { "\($0) wants to see your screen." }
    public var allowViewing = "Allow viewing"
    public var allowControl = "Allow viewing and control"
    public var deny = "Deny"
    public var viewing = "Support is viewing"
    public var controlling = "Support is controlling"
    public var viewOnly = "View only"
    public var end = "End"
    public var cancel = "Cancel"

    public init() {}
}

final class OverlayWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self || hit === rootViewController?.view ? nil : hit
    }
}

enum BannerPosition {
    static func clamped(_ center: CGPoint, size: CGSize, in area: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(center.x, area.minX + size.width / 2), area.maxX - size.width / 2),
            y: min(max(center.y, area.minY + size.height / 2), area.maxY - size.height / 2)
        )
    }
}

final class OverlayViewController: UIViewController {

    var onCancel: (() -> Void)?
    var onAllow: ((SessionMode) -> Void)?
    var onDeny: (() -> Void)?
    var onViewOnly: (() -> Void)?
    var onEnd: (() -> Void)?

    private let strings: SideSeatStrings
    private let tint: UIColor
    private let allowsControl: Bool
    private let showsConsent: Bool

    private let backdrop = UIView()
    private let card = UIStackView()
    private let titleLabel = UILabel()
    private let codeLabel = UILabel()
    private let messageLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let buttons = UIStackView()

    private let banner = UIView()
    private let dot = UIView()
    private let statusLabel = UILabel()
    private let viewOnlyButton = UIButton(type: .system)
    private let endButton = UIButton(type: .system)
    private var bannerX: NSLayoutConstraint?
    private var bannerY: NSLayoutConstraint?
    private var bannerMoved = false

    init(strings: SideSeatStrings, tint: UIColor, allowsControl: Bool, showsConsent: Bool) {
        self.strings = strings
        self.tint = tint
        self.allowsControl = allowsControl
        self.showsConsent = showsConsent
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        buildCard()
        buildBanner()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !bannerMoved else { return }
        bannerY?.constant = view.safeAreaInsets.top + 12 + banner.bounds.height / 2
    }

    func render(_ state: SessionState) {
        loadViewIfNeeded()
        backdrop.isHidden = true
        banner.isHidden = true
        switch state {
        case .connecting:
            showCard(title: strings.connecting, code: nil, message: nil, actions: [(strings.cancel, .plain, { [weak self] in self?.onCancel?() })])
        case .waitingForAgent(let code):
            showCard(title: strings.codeTitle, code: code, message: strings.codeMessage, actions: [(strings.cancel, .plain, { [weak self] in self?.onCancel?() })])
        case .awaitingConsent(_, let agent):
            guard showsConsent else { return }
            var actions: [(String, ButtonStyle, () -> Void)] = []
            if allowsControl { actions.append((strings.allowControl, .filled, { [weak self] in self?.onAllow?(.control) })) }
            actions.append((strings.allowViewing, allowsControl ? .tinted : .filled, { [weak self] in self?.onAllow?(.view) }))
            actions.append((strings.deny, .destructive, { [weak self] in self?.onDeny?() }))
            showCard(title: strings.consentTitle, code: nil, message: strings.consentMessage(agent.name), actions: actions)
        case .active(_, _, let mode):
            banner.isHidden = false
            statusLabel.text = mode == .control ? strings.controlling : strings.viewing
            viewOnlyButton.isHidden = mode != .control
            view.layoutIfNeeded()
            if bannerMoved { moveBanner(to: banner.center) }
        case .ended:
            break
        }
    }

    private enum ButtonStyle {
        case filled, tinted, plain, destructive
    }

    private func showCard(title: String, code: String?, message: String?, actions: [(String, ButtonStyle, () -> Void)]) {
        backdrop.isHidden = false
        titleLabel.text = title
        codeLabel.isHidden = code == nil
        codeLabel.text = code.map { $0.count == 6 ? "\($0.prefix(3)) \($0.suffix(3))" : $0 }
        codeLabel.accessibilityLabel = code.map { $0.map(String.init).joined(separator: " ") }
        messageLabel.isHidden = message == nil
        messageLabel.text = message
        let loading = code == nil && message == nil
        spinner.isHidden = !loading
        loading ? spinner.startAnimating() : spinner.stopAnimating()
        buttons.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (title, style, action) in actions {
            buttons.addArrangedSubview(makeButton(title, style: style, action: action))
        }
    }

    private func makeButton(_ title: String, style: ButtonStyle, action: @escaping () -> Void) -> UIButton {
        var configuration: UIButton.Configuration
        switch style {
        case .filled:
            configuration = .filled()
            configuration.baseBackgroundColor = tint
        case .tinted:
            configuration = .tinted()
            configuration.baseForegroundColor = tint
            configuration.baseBackgroundColor = tint
        case .plain:
            configuration = .plain()
            configuration.baseForegroundColor = tint
        case .destructive:
            configuration = .plain()
            configuration.baseForegroundColor = .systemRed
        }
        configuration.title = title
        configuration.cornerStyle = .large
        configuration.buttonSize = .large
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.accessibilityIdentifier = "sideseat.\(title)"
        return button
    }

    private func buildCard() {
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backdrop)

        let panel = UIView()
        panel.backgroundColor = .systemBackground
        panel.layer.cornerRadius = 22
        panel.layer.cornerCurve = .continuous
        panel.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(panel)

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center
        codeLabel.font = .monospacedDigitSystemFont(ofSize: 44, weight: .semibold)
        codeLabel.textColor = tint
        codeLabel.textAlignment = .center
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        buttons.axis = .vertical
        buttons.spacing = 8

        card.axis = .vertical
        card.spacing = 12
        card.alignment = .fill
        [titleLabel, codeLabel, messageLabel, spinner, buttons].forEach(card.addArrangedSubview)
        card.setCustomSpacing(20, after: messageLabel)
        card.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(card)

        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.centerXAnchor.constraint(equalTo: backdrop.centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: backdrop.centerYAnchor),
            panel.widthAnchor.constraint(equalToConstant: 340),
            card.topAnchor.constraint(equalTo: panel.topAnchor, constant: 24),
            card.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -16),
            card.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -20)
        ])
    }

    private func buildBanner() {
        let height: CGFloat = 36
        banner.backgroundColor = UIColor(white: 0.1, alpha: 0.94)
        banner.layer.cornerRadius = height / 2
        banner.layer.shadowColor = UIColor.black.cgColor
        banner.layer.shadowOpacity = 0.25
        banner.layer.shadowRadius = 8
        banner.layer.shadowOffset = CGSize(width: 0, height: 2)
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(bannerDragged(_:))))

        dot.backgroundColor = .systemRed
        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.3
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        dot.layer.add(pulse, forKey: "pulse")

        statusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        statusLabel.textColor = .white

        configureBannerButton(viewOnlyButton, title: strings.viewOnly, color: .white) { [weak self] in self?.onViewOnly?() }
        configureBannerButton(endButton, title: strings.end, color: UIColor(red: 1, green: 0.45, blue: 0.42, alpha: 1)) { [weak self] in self?.onEnd?() }

        let row = UIStackView(arrangedSubviews: [dot, statusLabel, viewOnlyButton, endButton])
        row.alignment = .center
        row.spacing = 10
        row.setCustomSpacing(6, after: viewOnlyButton)
        row.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(row)
        view.addSubview(banner)

        let x = banner.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        let y = banner.centerYAnchor.constraint(equalTo: view.topAnchor, constant: 40)
        bannerX = x
        bannerY = y
        NSLayoutConstraint.activate([
            x, y,
            banner.heightAnchor.constraint(equalToConstant: height),
            banner.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            row.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -5),
            row.centerYAnchor.constraint(equalTo: banner.centerYAnchor)
        ])
    }

    private func configureBannerButton(_ button: UIButton, title: String, color: UIColor, action: @escaping () -> Void) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseForegroundColor = color
        configuration.baseBackgroundColor = color.withAlphaComponent(0.18)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 13, weight: .bold)
            return attributes
        }
        button.configuration = configuration
        button.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
        button.accessibilityIdentifier = "sideseat.\(title)"
    }

    @objc private func bannerDragged(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: view)
        pan.setTranslation(.zero, in: view)
        bannerMoved = true
        moveBanner(to: CGPoint(x: banner.center.x + translation.x, y: banner.center.y + translation.y))
    }

    private func moveBanner(to center: CGPoint) {
        let area = view.bounds.inset(by: view.safeAreaInsets).insetBy(dx: 8, dy: 8)
        let point = BannerPosition.clamped(center, size: banner.bounds.size, in: area)
        bannerX?.constant = point.x - view.bounds.midX
        bannerY?.constant = point.y
        view.layoutIfNeeded()
    }
}
