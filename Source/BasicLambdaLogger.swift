//
//  BasicLambdaLogger.swift
//  AWSLambdaAdapter
//
//  Created by Kelton Person on 7/21/19.
//

import Foundation

#if os(Linux)
import Glibc
#else
import Darwin.C
#endif

public enum BasicLambdaLoggerLevel: Int {

    case debug = 0
    case info = 1
    case warn = 2
    case error = 3
    
    public init(str: String) {
        switch str.lowercased() {
        case "debug": self = .debug
        case "warn": self = .warn
        case "error": self = .error
        default: self = .info
        }
    }
    
    public var str: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        }
    }
    
}

class BasicLambdaLogger {
    
    let logLevel: BasicLambdaLoggerLevel
    
    init(logLevel: BasicLambdaLoggerLevel) {
        self.logLevel = logLevel
    }
    
    func log(
        string: String,
        level: BasicLambdaLoggerLevel,
        file: String = #file,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        if level.rawValue >= logLevel.rawValue {
            Swift.print("[\(level.str)] \(string) (\(file):\(function):\(line):\(column))")
            fflush(stdout)
        }
    }
    
    func error(
        error: Error,
        level: BasicLambdaLoggerLevel,
        file: String = #file,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        var errorText = ""
        print(error, to: &errorText)
        log(string: errorText, level: level)
    }
    
}
