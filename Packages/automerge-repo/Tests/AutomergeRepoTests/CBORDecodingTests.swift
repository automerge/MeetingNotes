import AutomergeRepo
import PotentCBOR
import XCTest

final class CBORDecodingTests: XCTestCase {
    func testCBORSerialization() throws {
        let peerMsg = SyncV1.PeerMsg(senderId: "senderUUID", targetId: "targetUUID", storageId: "something")
        let encodedPeerMsg = try SyncV1.encode(peerMsg)

        let x = try CBORSerialization.cbor(from: encodedPeerMsg)
        XCTAssertEqual(x.mapValue?["type"]?.utf8StringValue, SyncV1.MsgTypes.peer)
        // print("CBOR data: \(x)")
    }
}
