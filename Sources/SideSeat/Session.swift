import Foundation

public enum SessionState: Equatable {
    case connecting
    case waitingForAgent(code: String)
    case awaitingConsent(code: String, agent: Agent)
    case active(code: String, agent: Agent, mode: SessionMode)
    case ended(EndReason)
}

final class Session {

    var onStateChange: ((SessionState) -> Void)?
    var perform: ((RemoteInput) -> InputResult)?

    private(set) var state: SessionState = .connecting {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    private let transport: SideSeatTransport
    private let allowsControl: Bool

    init(transport: SideSeatTransport, allowsControl: Bool) {
        self.transport = transport
        self.allowsControl = allowsControl
    }

    var isStreaming: Bool {
        if case .active = state { return true }
        return false
    }

    func start() {
        transport.onText = { [weak self] in self?.receive($0) }
        transport.onClose = { [weak self] _ in self?.finish(.disconnected, notify: false) }
        transport.connect()
    }

    func receive(_ text: String) {
        guard let message = try? IncomingMessage(json: text) else { return }
        switch (message, state) {
        case (.session(let code), .connecting):
            state = .waitingForAgent(code: code)
        case (.agentJoined(let agent), .waitingForAgent(let code)):
            state = .awaitingConsent(code: code, agent: agent)
        case (.agentLeft, .awaitingConsent(let code, _)), (.agentLeft, .active(let code, _, _)):
            state = .waitingForAgent(code: code)
        case (.input(let id, let input), .active(_, _, .control)):
            send(.result(id: id, perform?(input) ?? .nothing("notAvailable")))
        case (.input(let id, _), .active(_, _, .view)):
            send(.result(id: id, .blocked("viewOnly")))
        case (.input(let id, _), _):
            send(.result(id: id, .blocked("noConsent")))
        case (.end(let reason), _):
            finish(reason, notify: false)
        default:
            break
        }
    }

    func grant(_ mode: SessionMode) {
        guard case .awaitingConsent(let code, let agent) = state else { return }
        let granted = allowsControl ? mode : .view
        send(.consent(granted))
        state = .active(code: code, agent: agent, mode: granted)
    }

    func deny() {
        guard case .awaitingConsent(let code, _) = state else { return }
        send(.denied)
        state = .waitingForAgent(code: code)
    }

    func switchToViewOnly() {
        guard case .active(let code, let agent, .control) = state else { return }
        send(.mode(.view))
        state = .active(code: code, agent: agent, mode: .view)
    }

    func end() {
        finish(.userEnded, notify: true)
    }

    func sendScreen(width: Double, height: Double) {
        send(.screen(width: width, height: height))
    }

    func sendFrame(_ jpeg: Data, completion: @escaping () -> Void) {
        transport.send(data: jpeg, completion: completion)
    }

    private func send(_ message: OutgoingMessage) {
        transport.send(text: message.json)
    }

    private func finish(_ reason: EndReason, notify: Bool) {
        if case .ended = state { return }
        if notify { send(.end(reason)) }
        state = .ended(reason)
        transport.close()
    }
}
