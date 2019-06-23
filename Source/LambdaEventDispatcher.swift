import Foundation
import NIOHTTPClient
import NIO

public protocol LambdaEventHandler {
    
    func handle(data: [String: Any], eventLoop: EventLoop) -> EventLoopFuture<[String : Any]>
    
}

public class LambdaEventDispatcher {

    let handler: LambdaEventHandler
    let runtimeAPI: String
    
    let httpClient = HTTPClient(
        eventLoopGroupProvider: .createNew,
        configuration: HTTPClient.Configuration(followRedirects: true)
    )
    
    public init(handler: LambdaEventHandler, runtimeAPI: String? = nil) {
        self.handler = handler
        self.runtimeAPI = runtimeAPI
            ?? ProcessInfo.processInfo.environment["AWS_LAMBDA_RUNTIME_API"]
            ?? "localhost:8080"
    }
    
    public func run() {
        let nextEndpoint = "http://\(runtimeAPI)/2018-06-01/runtime/invocation/next"
        let cycle = httpClient.get(
            url: nextEndpoint,
            timeout: HTTPClient.Timeout(
                connect: TimeAmount.milliseconds(Int64(2000)),
                read: TimeAmount.microseconds(Int64(20000))
            )
        ).flatMap { res -> EventLoopFuture<Void> in
            if let requestId = res.headers["Lambda-Runtime-Aws-Request-Id"].first, let buffer = res.body {
                return self.handleJob(data: buffer.data, requestId: requestId)
            }
            else {
                return self.httpClient.eventLoopGroup.next().makeSucceededFuture(Void())
            }
        }
        
        defer {
            run()
        }
        do {
            try cycle.wait()
        }
        catch let error {
            print("unhandled error: \(error)")
        }
    }
    
    private func handleJob(
        data: Data,
        requestId: String
    ) -> EventLoopFuture<Void> {
        do {
            let map = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
            return handler.handle(data: map, eventLoop: httpClient.eventLoopGroup.next())
                .flatMap { results in self.handleSuccessJob(response: results, requestId: requestId) }
                .flatMapError { error in
                    self.handleFailedJob(
                        response: LambdaEventDispatcher.errorResponse(error: error),
                        requestId: requestId
                    )
                }
        }
        catch let error {
            return self.handleFailedJob(
                response: LambdaEventDispatcher.errorResponse(error: error),
                requestId: requestId
            )
        }
    }
    
    private func handleSuccessJob(
        response: [String: Any],
        requestId: String
    ) -> EventLoopFuture<Void> {
        let endpoint = "http://\(runtimeAPI)/2018-06-01/runtime/invocation/\(requestId)/response"
        return postResponse(response: response, requestId: requestId, endpoint: endpoint)

    }
    
    private func handleFailedJob(
        response: [String: Any],
        requestId: String
    ) -> EventLoopFuture<Void> {
        let endpoint = "http://\(runtimeAPI)/2018-06-01/runtime/invocation/\(requestId)/error"
        return postResponse(response: response, requestId: requestId, endpoint: endpoint)
    }
    
    private func postResponse(
        response: [String: Any],
        requestId: String,
        endpoint: String
    ) -> EventLoopFuture<Void> {
        let data = try! JSONSerialization.data(withJSONObject: response, options: [])
        return httpClient.post(url: endpoint, body: .data(data)).map { _ in Void() }
    }
    
    static func errorResponse(error: Error) -> [String: Any] {
        var errorText = ""
        print(error, to: &errorText)
        return [
            "errorLocalizedDescription": error.localizedDescription,
            "errorDetails": errorText
        ]
    }
    
}
