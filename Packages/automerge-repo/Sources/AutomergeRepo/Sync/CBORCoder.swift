import Foundation
import PotentCBOR

/// A type that provides concurrency-safe access to the CBOR encoder and decoder.
public actor CBORCoder {
    public static let encoder = CBOREncoder()
    public static let decoder = CBORDecoder()
}
