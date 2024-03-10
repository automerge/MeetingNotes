import Foundation
import PotentCBOR

/// A type that provides concurrency-safe access to the CBOR encoder and decoder.
actor CBORCoder {
    static let encoder = CBOREncoder()
    static let decoder = CBORDecoder()
}
