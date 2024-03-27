/*

 Copyright © 2022 Apple Inc.

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

  WWDC Video references aligned with this code:
  - https://developer.apple.com/videos/play/wwdc2019/713/
  - https://developer.apple.com/videos/play/wwdc2020/10110/
  */

import Foundation
import Network
import OSLog

/// The type of sync message for the Automerge network sync protocol.
enum P2PSyncMessageType: UInt32 {
    case unknown = 0 // msg isn't a recognized type
    case sync = 1 // msg is generated sync data to merge into an Automerge document
    case id = 2 // msg is a unique for the source/master of a document to know if they've been cloned
    case peer = 3
    case join = 4
    case request = 5
    case unavailable = 6
    case ephemeral = 7
    case syncerror = 8
    case remoteHeadsChanged = 9
    case remoteSubscriptionChange = 10
    case leave = 11
}

/// The definition of the Automerge network sync protocol.
class P2PAutomergeSyncProtocol: NWProtocolFramerImplementation {
    // Create a global definition of your game protocol to add to connections.
    static let definition = NWProtocolFramer.Definition(implementation: P2PAutomergeSyncProtocol.self)

    // Set a name for your protocol for use in debugging.
    static var label: String { "AutomergeSync" }

    static var bonjourType: String { "_automergesync._tcp" }
    static var applicationService: String { "AutomergeSync" }

    // Set the default behavior for most framing protocol functions.
    required init(framer _: NWProtocolFramer.Instance) {}
    func start(framer _: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult { .ready }
    func wakeup(framer _: NWProtocolFramer.Instance) {}
    func stop(framer _: NWProtocolFramer.Instance) -> Bool { true }
    func cleanup(framer _: NWProtocolFramer.Instance) {}

    // Whenever the application sends a message, add your protocol header and forward the bytes.
    func handleOutput(
        framer: NWProtocolFramer.Instance,
        message: NWProtocolFramer.Message,
        messageLength: Int,
        isComplete _: Bool
    ) {
        // Extract the type of message.
        let type = message.syncMessageType

        // Create a header using the type and length.
        let header = P2PAutomergeSyncProtocolHeader(type: type.rawValue, length: UInt32(messageLength))

        // Write the header.
        framer.writeOutput(data: header.encodedData)

        // Ask the connection to insert the content of the app message after your header.
        do {
            try framer.writeOutputNoCopy(length: messageLength)
        } catch {
            Logger.syncController.error("Error writing protocol data into frame: \(error, privacy: .public)")
        }
    }

    // Whenever new bytes are available to read, try to parse out your message format.
    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        while true {
            // Try to read out a single header.
            var tempHeader: P2PAutomergeSyncProtocolHeader? = nil
            let headerSize = P2PAutomergeSyncProtocolHeader.encodedSize
            let parsed = framer.parseInput(
                minimumIncompleteLength: headerSize,
                maximumLength: headerSize
            ) { buffer, _ -> Int in
                guard let buffer else {
                    return 0
                }
                if buffer.count < headerSize {
                    return 0
                }
                tempHeader = P2PAutomergeSyncProtocolHeader(buffer)
                return headerSize
            }

            // If you can't parse out a complete header, stop parsing and return headerSize,
            // which asks for that many more bytes.
            guard parsed, let header = tempHeader else {
                return headerSize
            }

            // Create an object to deliver the message.
            var messageType = P2PSyncMessageType.unknown
            if let parsedMessageType = P2PSyncMessageType(rawValue: header.type) {
                messageType = parsedMessageType
            }
            let message = NWProtocolFramer.Message(syncMessageType: messageType)

            // Deliver the body of the message, along with the message object.
            if !framer.deliverInputNoCopy(length: Int(header.length), message: message, isComplete: true) {
                return 0
            }
        }
    }
}

// Extend framer messages to handle storing your command types in the message metadata.
extension NWProtocolFramer.Message {
    /// Create a new protocol-framed message for the Automerge network sync protocol.
    /// - Parameter syncMessageType: The type of sync message for this Automerge peer to peer sync protocol
    convenience init(syncMessageType: P2PSyncMessageType) {
        self.init(definition: P2PAutomergeSyncProtocol.definition)
        self["SyncMessageType"] = syncMessageType
    }

    /// The type of sync message.
    var syncMessageType: P2PSyncMessageType {
        if let type = self["SyncMessageType"] as? P2PSyncMessageType {
            type
        } else {
            .unknown
        }
    }
}

// Define a protocol header structure to help encode and decode bytes.

/// The Automerge network sync protocol header structure.
struct P2PAutomergeSyncProtocolHeader: Codable {
    let type: UInt32
    let length: UInt32

    init(type: UInt32, length: UInt32) {
        self.type = type
        self.length = length
    }

    init(_ buffer: UnsafeMutableRawBufferPointer) {
        var tempType: UInt32 = 0
        var tempLength: UInt32 = 0
        withUnsafeMutableBytes(of: &tempType) { typePtr in
            typePtr.copyMemory(from: UnsafeRawBufferPointer(
                start: buffer.baseAddress!.advanced(by: 0),
                count: MemoryLayout<UInt32>.size
            ))
        }
        withUnsafeMutableBytes(of: &tempLength) { lengthPtr in
            lengthPtr
                .copyMemory(from: UnsafeRawBufferPointer(
                    start: buffer.baseAddress!
                        .advanced(by: MemoryLayout<UInt32>.size),
                    count: MemoryLayout<UInt32>.size
                ))
        }
        type = tempType
        length = tempLength
    }

    var encodedData: Data {
        var tempType = type
        var tempLength = length
        var data = Data(bytes: &tempType, count: MemoryLayout<UInt32>.size)
        data.append(Data(bytes: &tempLength, count: MemoryLayout<UInt32>.size))
        return data
    }

    static var encodedSize: Int {
        MemoryLayout<UInt32>.size * 2
    }
}
