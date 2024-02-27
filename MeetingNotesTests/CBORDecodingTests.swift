//
//  CBORDecodingTests.swift
//  MeetingNotesTests
//
//  Created by Joseph Heck on 2/27/24.
//

import MeetingNotes
import PotentCBOR
import XCTest

final class CBORDecodingTests: XCTestCase {
    func testCBORSerialization() throws {
        let peerMsg = PeerMsg(senderId: "senderUUID", targetId: "targetUUID", storageId: "something")
        let encodedPeerMsg = try V1Msg.encode(peerMsg)

        let x = try CBORSerialization.cbor(from: encodedPeerMsg)
        XCTAssertEqual(x.mapValue?["type"]?.utf8StringValue, V1Msg.MTypes.peer.rawValue)
        // print("CBOR data: \(x)")
    }
}
