import Foundation

struct UnconfiguredTestNetwork: LocalizedError {
    public var errorDescription: String? {
        "The test network is not configured."
    }
}
