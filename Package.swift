// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "aws-lambda-adapater",
    products: [
        .library(name: "AWSLambdaAdapter", targets: ["AWSLambdaAdapter"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "1.13.0")
    ],
    targets: [
        .target(
            name: "AWSLambdaAdapter", 
            dependencies: [
                "NIO"
            ],
            path: "./Source"
        )
    ]
)
