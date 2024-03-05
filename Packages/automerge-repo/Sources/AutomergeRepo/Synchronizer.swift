import protocol Combine.Publisher
import struct Foundation.UUID

// loose adaptation from
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo/src/synchronizer/Synchronizer.ts
protocol Synchronizer {
    var peerId: UUID { get }
    associatedtype MessagePublisher: Publisher<SyncV1.EphemeralMsg, Never>
    var messages: MessagePublisher { get }
}
