// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "AWSLambdaAdapter",
    products: [
        .library(name: "adapter", targets: ["AWSLambdaAdapter"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/swift-nio-http-client.git", .branch("master"))
    ],
    targets: [
        .target(
            name: "AWSLambdaAdapter", 
            dependencies: [
                "NIOHTTPClient"
            ],
            path: "./Source"
        )
    ]
)
