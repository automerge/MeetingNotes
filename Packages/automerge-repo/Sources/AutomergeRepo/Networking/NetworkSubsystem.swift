import class Combine.PassthroughSubject
import struct Foundation.Data

// riff
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo/src/network/NetworkSubsystem.ts
/// A type that hosts network subsystems to connect and synchronize data related to Automerge documents.
public struct NetworkSubsystem {
    var adapters: [any NetworkSyncProvider]

    init(adapters: [any NetworkSyncProvider]) {
        self.adapters = adapters
    }

    func send(message _: Data) {}
    func isReady() async -> Bool {
        false
    }

    func whenReady() async {}

    let eventPublisher: PassthroughSubject<NetworkAdapterEvents, Never> = PassthroughSubject()
}
