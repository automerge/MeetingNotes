import AutomergeRepo
import PotentCBOR
import XCTest

final class CBORDecodingTests: XCTestCase {
    func testCBORSerialization() throws {
        let peerMsg = SyncV1Msg.PeerMsg(senderId: "senderUUID", targetId: "targetUUID", storageId: "something")
        let encodedPeerMsg = try SyncV1Msg.encode(peerMsg)

        let x = try CBORSerialization.cbor(from: encodedPeerMsg)
        XCTAssertEqual(x.mapValue?["type"]?.utf8StringValue, SyncV1Msg.MsgTypes.peer)
        // print("CBOR data: \(x)")
    }
}
