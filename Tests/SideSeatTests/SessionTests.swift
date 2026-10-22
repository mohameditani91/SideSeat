import Foundation
import Testing
@testable import SideSeat

final class FakeTransport: SideSeatTransport {
    var onText: ((String) -> Void)?
    var onClose: ((Error?) -> Void)?
    var sent: [String] = []
    var frames = 0
    var connected = false
    var closed = false

    func connect() { connected = true }
    func send(text: String) { sent.append(text) }
    func send(data: Data, completion: @escaping () -> Void) {
        frames += 1
        completion()
    }
    func close() { closed = true }

    func deliver(_ json: String) { onText?(json) }
    var lastSent: String? { sent.last }
}

@Suite struct SessionTests {

    private func activeSession(mode: SessionMode, allowsControl: Bool = true) -> (Session, FakeTransport) {
        let transport = FakeTransport()
        let session = Session(transport: transport, allowsControl: allowsControl)
        session.start()
        transport.deliver(#"{"type":"session","code":"123456"}"#)
        transport.deliver(#"{"type":"agentJoined","agentId":"a1","agentName":"Sara"}"#)
        session.grant(mode)
        return (session, transport)
    }

    @Test func walksFromCodeToConsentToActive() {
        let transport = FakeTransport()
        let session = Session(transport: transport, allowsControl: true)
        var states: [SessionState] = []
        session.onStateChange = { states.append($0) }

        session.start()
        #expect(transport.connected)
        transport.deliver(#"{"type":"session","code":"123456"}"#)
        transport.deliver(#"{"type":"agentJoined","agentId":"a1","agentName":"Sara"}"#)
        session.grant(.control)

        let sara = Agent(id: "a1", name: "Sara")
        #expect(states == [
            .waitingForAgent(code: "123456"),
            .awaitingConsent(code: "123456", agent: sara),
            .active(code: "123456", agent: sara, mode: .control)
        ])
        #expect(transport.lastSent == #"{"mode":"control","type":"consent"}"#)
    }

    @Test func controlRunsInputsAndReportsTheResult() {
        let (session, transport) = activeSession(mode: .control)
        var performed: [RemoteInput] = []
        session.perform = { performed.append($0); return .nothing("noTarget") }

        transport.deliver(#"{"type":"input","id":"i1","action":"tap","x":0.5,"y":0.25}"#)

        #expect(performed == [.tap(x: 0.5, y: 0.25)])
        #expect(transport.lastSent == #"{"id":"i1","outcome":"nothing","reason":"noTarget","type":"result"}"#)
    }

    @Test func viewOnlyBlocksInputs() {
        let (session, transport) = activeSession(mode: .view)
        session.perform = { _ in Issue.record("must not run"); return .performed }
        transport.deliver(#"{"type":"input","id":"i1","action":"back"}"#)
        #expect(transport.lastSent == #"{"id":"i1","outcome":"blocked","reason":"viewOnly","type":"result"}"#)
    }

    @Test func inputsBeforeConsentAreBlocked() {
        let transport = FakeTransport()
        let session = Session(transport: transport, allowsControl: true)
        session.start()
        transport.deliver(#"{"type":"session","code":"123456"}"#)
        transport.deliver(#"{"type":"input","id":"i1","action":"text","text":"hi"}"#)
        #expect(transport.lastSent == #"{"id":"i1","outcome":"blocked","reason":"noConsent","type":"result"}"#)
    }

    @Test func controlIsDowngradedWhenTheAppDisallowsIt() {
        let (session, transport) = activeSession(mode: .control, allowsControl: false)
        #expect(session.state == .active(code: "123456", agent: Agent(id: "a1", name: "Sara"), mode: .view))
        #expect(transport.lastSent == #"{"mode":"view","type":"consent"}"#)
    }

    @Test func switchingToViewOnlyTellsTheAgent() {
        let (session, transport) = activeSession(mode: .control)
        session.switchToViewOnly()
        #expect(session.state == .active(code: "123456", agent: Agent(id: "a1", name: "Sara"), mode: .view))
        #expect(transport.lastSent == #"{"mode":"view","type":"mode"}"#)
    }

    @Test func denyingSendsTheAgentAwayAndKeepsTheCode() {
        let transport = FakeTransport()
        let session = Session(transport: transport, allowsControl: true)
        session.start()
        transport.deliver(#"{"type":"session","code":"123456"}"#)
        transport.deliver(#"{"type":"agentJoined","agentId":"a1","agentName":"Sara"}"#)
        session.deny()
        #expect(session.state == .waitingForAgent(code: "123456"))
        #expect(transport.lastSent == #"{"type":"denied"}"#)
    }

    @Test func theAgentLeavingReturnsToTheCode() {
        let (session, transport) = activeSession(mode: .control)
        transport.deliver(#"{"type":"agentLeft"}"#)
        #expect(session.state == .waitingForAgent(code: "123456"))
    }

    @Test func endingNotifiesTheRelayOnce() {
        let (session, transport) = activeSession(mode: .control)
        session.end()
        session.end()
        #expect(session.state == .ended(.userEnded))
        #expect(transport.sent.filter { $0.contains(#""type":"end""#) }.count == 1)
        #expect(transport.closed)
    }

    @Test func theAgentEndingOrTheSocketDroppingEndsTheSession() {
        let (agentEnded, first) = activeSession(mode: .view)
        first.deliver(#"{"type":"end","reason":"agentEnded"}"#)
        #expect(agentEnded.state == .ended(.agentEnded))

        let (dropped, second) = activeSession(mode: .view)
        second.onClose?(nil)
        #expect(dropped.state == .ended(.disconnected))
    }

    @Test func malformedMessagesAreIgnored() {
        let transport = FakeTransport()
        let session = Session(transport: transport, allowsControl: true)
        session.start()
        transport.deliver("not json")
        transport.deliver(#"{"type":"session"}"#)
        transport.deliver(#"{"type":"input","id":"i1","action":"tap"}"#)
        #expect(session.state == .connecting)
    }

    @Test func decodesEveryInput() throws {
        #expect(try IncomingMessage(json: #"{"type":"input","id":"1","action":"scroll","x":0.1,"y":0.2,"dx":0,"dy":0.3}"#) == .input(id: "1", .scroll(x: 0.1, y: 0.2, dx: 0, dy: 0.3)))
        #expect(try IncomingMessage(json: #"{"type":"input","id":"2","action":"key","key":"return"}"#) == .input(id: "2", .key(.return)))
        #expect(try IncomingMessage(json: #"{"type":"input","id":"3","action":"key","key":"backspace"}"#) == .input(id: "3", .key(.backspace)))
        #expect(try IncomingMessage(json: #"{"type":"input","id":"4","action":"text","text":"ab"}"#) == .input(id: "4", .text("ab")))
        #expect(throws: MessageError.self) { try IncomingMessage(json: #"{"type":"input","id":"5","action":"swipe"}"#) }
    }

    @Test func framesRateDropsWhenCaptureIsSlowAndRecovers() {
        var policy = FrameRatePolicy(maxFps: 2, budget: 0.05)
        let slow = (0..<3).map { _ in policy.record(0.08) }
        #expect(slow == [false, false, true])
        #expect(policy.fps == 1)
        let fast = (0..<10).map { _ in policy.record(0.01) }
        #expect(fast == Array(repeating: false, count: 9) + [true])
        #expect(policy.fps == 2)
        for _ in 0..<30 { _ = policy.record(0.5) }
        #expect(policy.fps == FrameRatePolicy.floor)
    }
}
