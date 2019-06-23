//
//  ByteBufferExtensions.swift
//  CNIOAtomics
//
//  Created by Kelton Person on 6/22/19.
//

import NIO
import Foundation

extension ByteBuffer {

    var data: Data {
        var mutableSelf = self
        var d = Data(capacity: mutableSelf.readableBytes)
        while let bytes = mutableSelf.readBytes(length: max(min(1024, mutableSelf.readableBytes), 1)) {
            d.append(Data(bytes: bytes))
        }
        return d
    }
    
}
