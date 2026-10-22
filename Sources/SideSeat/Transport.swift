import Foundation

/// Carries messages between the app and a relay. Callbacks must be delivered on the main queue.
public protocol SideSeatTransport: AnyObject {
    var onText: ((String) -> Void)? { get set }
    var onClose: ((Error?) -> Void)? { get set }
    func connect()
    func send(text: String)
    func send(data: Data, completion: @escaping () -> Void)
    func close()
}

/// The default transport: a WebSocket to the relay. Put authentication in the request (headers or query).
public final class WebSocketTransport: NSObject, SideSeatTransport {

    public var onText: ((String) -> Void)?
    public var onClose: ((Error?) -> Void)?

    private let request: URLRequest
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var isClosed = false

    public init(request: URLRequest) {
        self.request = request
    }

    public func connect() {
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        self.session = session
        self.task = task
        task.resume()
        receive()
    }

    public func send(text: String) {
        task?.send(.string(text)) { [weak self] error in
            guard let error else { return }
            DispatchQueue.main.async { self?.finish(error) }
        }
    }

    public func send(data: Data, completion: @escaping () -> Void) {
        task?.send(.data(data)) { [weak self] error in
            DispatchQueue.main.async {
                completion()
                if let error { self?.finish(error) }
            }
        }
    }

    public func close() {
        isClosed = true
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
    }

    private func receive() {
        task?.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self, !self.isClosed else { return }
                switch result {
                case .success(.string(let text)):
                    self.onText?(text)
                    self.receive()
                case .success:
                    self.receive()
                case .failure(let error):
                    self.finish(error)
                }
            }
        }
    }

    private func finish(_ error: Error?) {
        guard !isClosed else { return }
        close()
        onClose?(error)
    }
}
