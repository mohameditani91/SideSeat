import Foundation

public struct Agent: Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum SessionMode: String, Codable {
    case view
    case control
}

public enum EndReason: String, Codable {
    case userEnded
    case agentEnded
    case disconnected
}

public enum RemoteKey: String, Codable {
    case backspace
    case `return`
}

public enum RemoteInput: Equatable {
    case tap(x: Double, y: Double)
    case scroll(x: Double, y: Double, dx: Double, dy: Double)
    case text(String)
    case key(RemoteKey)
    case back
}

public struct InputResult: Equatable {
    public enum Outcome: String, Codable {
        case performed
        case nothing
        case blocked
    }

    public var outcome: Outcome
    public var reason: String?

    public init(outcome: Outcome, reason: String? = nil) {
        self.outcome = outcome
        self.reason = reason
    }

    public static let performed = InputResult(outcome: .performed)
    public static func nothing(_ reason: String) -> InputResult { InputResult(outcome: .nothing, reason: reason) }
    public static func blocked(_ reason: String) -> InputResult { InputResult(outcome: .blocked, reason: reason) }
}

enum IncomingMessage: Equatable {
    case session(code: String)
    case agentJoined(Agent)
    case agentLeft
    case input(id: String, RemoteInput)
    case end(EndReason)
}

enum OutgoingMessage: Equatable {
    case consent(SessionMode)
    case denied
    case screen(width: Double, height: Double)
    case result(id: String, InputResult)
    case mode(SessionMode)
    case end(EndReason)
}

private struct Envelope: Codable {
    var type: String
    var code: String?
    var agentId: String?
    var agentName: String?
    var id: String?
    var action: String?
    var x: Double?
    var y: Double?
    var dx: Double?
    var dy: Double?
    var text: String?
    var key: RemoteKey?
    var mode: SessionMode?
    var reason: String?
    var outcome: InputResult.Outcome?
    var width: Double?
    var height: Double?

    init(type: String) {
        self.type = type
    }
}

enum MessageError: Error {
    case malformed
}

extension IncomingMessage {

    init(json: String) throws {
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(json.utf8))
        switch envelope.type {
        case "session":
            guard let code = envelope.code else { throw MessageError.malformed }
            self = .session(code: code)
        case "agentJoined":
            guard let id = envelope.agentId, let name = envelope.agentName else { throw MessageError.malformed }
            self = .agentJoined(Agent(id: id, name: name))
        case "agentLeft":
            self = .agentLeft
        case "input":
            guard let id = envelope.id else { throw MessageError.malformed }
            self = .input(id: id, try Self.input(from: envelope))
        case "end":
            self = .end(envelope.reason.flatMap(EndReason.init(rawValue:)) ?? .agentEnded)
        default:
            throw MessageError.malformed
        }
    }

    private static func input(from envelope: Envelope) throws -> RemoteInput {
        switch envelope.action {
        case "tap":
            guard let x = envelope.x, let y = envelope.y else { throw MessageError.malformed }
            return .tap(x: x, y: y)
        case "scroll":
            guard let x = envelope.x, let y = envelope.y, let dx = envelope.dx, let dy = envelope.dy else { throw MessageError.malformed }
            return .scroll(x: x, y: y, dx: dx, dy: dy)
        case "text":
            guard let text = envelope.text else { throw MessageError.malformed }
            return .text(text)
        case "key":
            guard let key = envelope.key else { throw MessageError.malformed }
            return .key(key)
        case "back":
            return .back
        default:
            throw MessageError.malformed
        }
    }
}

extension OutgoingMessage {

    var json: String {
        var envelope: Envelope
        switch self {
        case .consent(let mode):
            envelope = Envelope(type: "consent")
            envelope.mode = mode
        case .denied:
            envelope = Envelope(type: "denied")
        case .screen(let width, let height):
            envelope = Envelope(type: "screen")
            envelope.width = width
            envelope.height = height
        case .result(let id, let result):
            envelope = Envelope(type: "result")
            envelope.id = id
            envelope.outcome = result.outcome
            envelope.reason = result.reason
        case .mode(let mode):
            envelope = Envelope(type: "mode")
            envelope.mode = mode
        case .end(let reason):
            envelope = Envelope(type: "end")
            envelope.reason = reason.rawValue
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: (try? encoder.encode(envelope)) ?? Data(), as: UTF8.self)
    }
}
