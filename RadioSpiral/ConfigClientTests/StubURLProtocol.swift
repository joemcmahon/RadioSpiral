//
//  StubURLProtocol.swift
//  ConfigClientTests
//
//  Canned HTTP responses, so client tests run with no network. The real URLSession still
//  runs, so status codes, errors and response types reach the client as they would live.
//

import Foundation

final class StubURLProtocol: URLProtocol {

    enum Reply {
        case http(status: Int, body: Data = Data())
        case failure(URLError.Code)
    }

    private static let lock = NSLock()
    private static var replies: [String: Reply] = [:]
    private static var seen: [URLRequest] = []

    /// A session whose every request is answered here. A URL with no reply fails, and is
    /// still recorded, so an unexpected request can't reach the network or go unnoticed.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func reply(to url: String, with reply: Reply) {
        lock.lock(); defer { lock.unlock() }
        replies[url] = reply
    }

    /// Every URL requested, in the order the requests started.
    static var requestedURLs: [String] {
        lock.lock(); defer { lock.unlock() }
        return seen.compactMap { $0.url?.absoluteString }
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        replies = [:]
        seen = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let client = client, let url = request.url else { return }

        Self.lock.lock()
        Self.seen.append(request)
        let reply = Self.replies[url.absoluteString] ?? .failure(.cannotFindHost)
        Self.lock.unlock()

        switch reply {
        case .failure(let code):
            client.urlProtocol(self, didFailWithError: URLError(code))
        case .http(let status, let body):
            guard let response = HTTPURLResponse(url: url, statusCode: status,
                                                 httpVersion: "HTTP/1.1", headerFields: nil) else {
                client.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: body)
            client.urlProtocolDidFinishLoading(self)
        }
    }
}
