import AutomergeUniffi

// NOT NEEDED AFTER AUTOMERGE 0.5.7 - was added into core
import Foundation

extension AutomergeUniffi.DocError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .WrongObjectType(message: msg):
            return "WrongObjectType: \(msg)"
        case let .Internal(message: msg):
            return "AutomergeCore Internal Error: \(msg)"
        }
    }
}
