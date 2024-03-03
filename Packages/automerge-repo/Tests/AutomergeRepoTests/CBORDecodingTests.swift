import PotentCBOR
import AutomergeRepo
import XCTest

final class CBORDecodingTests: XCTestCase {
    func testCBORSerialization() throws {
        let peerMsg = V1.PeerMsg(senderId: "senderUUID", targetId: "targetUUID", storageId: "something")
        let encodedPeerMsg = try V1.encode(peerMsg)

        let x = try CBORSerialization.cbor(from: encodedPeerMsg)
        XCTAssertEqual(x.mapValue?["type"]?.utf8StringValue, V1.MsgTypes.peer)
        // print("CBOR data: \(x)")
    }
}
