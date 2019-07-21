import Foundation
import NIO

#if os(Linux)
import Glibc
#else
import Darwin.C
#endif


public protocol LambdaEventHandler {
    
    func handle(data: [String: Any], headers: [String : Any], eventLoopGroup: EventLoopGroup) -> EventLoopFuture<[String : Any]>
    
}

public class LambdaEventDispatcher {

    let handler: LambdaEventHandler
    let runtimeAPI: String
    var isRunning: Bool = false
    
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 3)
    let logger: BasicLambdaLogger
    
    public init(
        handler: LambdaEventHandler,
        runtimeAPI: String? = nil,
        logLevel: BasicLambdaLoggerLevel = .error
    ) {
        self.logger = BasicLambdaLogger(logLevel: logLevel)
        self.handler = handler
        self.runtimeAPI = runtimeAPI
            ?? ProcessInfo.processInfo.environment["AWS_LAMBDA_RUNTIME_API"]
            ?? "localhost:8080"
    }
    
    public func stop() {
        isRunning = false
    }
    
    public func start() -> EventLoopFuture<Void> {
        isRunning = true
        return run()
    }
    
    private func run() -> EventLoopFuture<Void> {
        if isRunning {
            let nextEndpoint = "http://\(runtimeAPI)/2018-06-01/runtime/invocation/next"
            logger.log(string: "making lambda event request: \(nextEndpoint)", level: .debug)
            return request(method: "GET", url: nextEndpoint, body: nil)
            .then { res -> EventLoopFuture<Void> in
                if let requestId = res.headers["Lambda-Runtime-Aws-Request-Id".lowercased()] as? String {
                    self.logger.log(string: "starting to handle lambda job: \(requestId)", level: .info)
                    return self.handleJob(data: res.body, headers: res.headers, requestId: requestId)
                }
                else {
                    self.logger.log(string: "no job found", level: .debug)
                    return self.eventLoopGroup.next().newSucceededFuture(result: Void())
                }
            }.then { _ in
                self.logger.log(string: "job complete, make another request", level: .debug)
                return self.run()
            }.thenIfError { _ in
                self.logger.log(string: "no job request failed", level: .debug)
                return self.run()
            }
        }
        else {
            return eventLoopGroup.next().newSucceededFuture(result: Void())
        }
    }
    
    private func handleJob(
        data: Data,
        headers: [String : Any],
        requestId: String
    ) -> EventLoopFuture<Void> {
        do {
            let map = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
            return handler.handle(data: map, headers: headers, eventLoopGroup: eventLoopGroup.next())
                .then { results in
                    self.logger.log(string: "job succeeded", level: .info)
                    return self.handleSuccessJob(response: results, requestId: requestId) }
                .thenIfError { error in
                    self.logger.error(error: error, level: .warn)
                    return self.handleFailedJob(
                        response: LambdaEventDispatcher.errorResponse(error: error),
                        requestId: requestId
                    )
                }
        }
        catch let error {
            self.logger.error(error: error, level: .error)
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
        return request(method: "POST", url: endpoint, body: data).map { _  in Void() }
    }
    
    static func errorResponse(error: Error) -> [String: Any] {
        var errorText = ""
        print(error, to: &errorText)
        return [
            "errorLocalizedDescription": error.localizedDescription,
            "errorDetails": errorText
        ]
    }
    
    func request(
        method: String,
        url: String,
        body: Data?,
        timeout: TimeInterval = 60
    ) -> EventLoopFuture<RequestResponse> {
        let p = eventLoopGroup.next().newPromise(of: RequestResponse.self)
        var request = URLRequest(
            url: URL(string: url)!,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: timeout
        )
        request.httpMethod = method
        request.httpBody = body
        
        let session = URLSession.shared
        let task = session.dataTask(with: request, completionHandler: { data, response, error -> Void in
            if let e = error {
                p.fail(error: e)
            }
            else {
                let httpResponse = response as! HTTPURLResponse
                var responseHeaders:Dictionary<String, Any> = [:]
                for (headerKey, headerValue) in httpResponse.allHeaderFields {
                    let hk = (headerKey as! String)
                    responseHeaders[hk.lowercased()] = headerValue
                }
                let res = RequestResponse(statusCode: httpResponse.statusCode, body: data!, headers: responseHeaders)
                p.succeed(result: res)
            }
        })
        task.resume()
        return p.futureResult
    }
    
}


public class RequestResponse {
    
    
    public let statusCode: Int
    public let body: Data
    public let headers: Dictionary<String, Any>
    
    private var bodyText: String?
    
    init(statusCode: Int, body: Data, headers: Dictionary<String, Any>) {
        self.statusCode = statusCode
        self.body = body
        self.headers = headers
    }
    
    public var bodyAsText: String {
        if let bodyT = self.bodyText {
            return bodyT
        }
        else {
            self.bodyText = NSString(data: body, encoding: String.Encoding.utf8.rawValue)! as String
            return self.bodyText!
        }
    }
    
}
