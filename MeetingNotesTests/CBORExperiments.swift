//
//  CBORExperiments.swift
//  MeetingNotesTests
//
//  Created by Joseph Heck on 1/28/24.
//

import PotentCBOR
import XCTest

// public extension Data {
//    func hexEncodedString(uppercase: Bool = false) -> String {
//        let format = uppercase ? "%02hhX" : "%02hhx"
//        return map { String(format: format, $0) }.joined()
//    }
// }

struct AnotherType: Codable {
    var name: String
    var blah: Data
}

struct Message: Codable {
    var first: String
    var second: Int?
    var notexisting: AnotherType?
}

struct ExtendedMessage: Codable {
    var first: String
    var second: Int
    var third: String
    var fourth: AnotherType?
}

final class CBORExperiments: XCTestCase {
    static let encoder = CBOREncoder()
    static let decoder = CBORDecoder()

    func testDecodingWithAdditionalData() throws {
        let data = try Self.encoder.encode(ExtendedMessage(
            first: "one",
            second: 2,
            third: "three",
            fourth: AnotherType(name: "foo", blah: Data())
        ))
        print("Encoded form: \(data.hexEncodedString())")
        // data format decoded with CBOR.me:
        // {"first": "one", "second": 2, "third": "three", "fourth": {"name": "foo", "blah": h''}}
        let decodedData = try Self.decoder.decode(Message.self, from: data)
        XCTAssertEqual(decodedData.first, "one")
        XCTAssertEqual(decodedData.second, 2)
    }
}
