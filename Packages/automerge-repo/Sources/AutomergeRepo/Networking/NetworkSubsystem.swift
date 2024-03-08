import class Combine.PassthroughSubject
import struct Foundation.Data

// riff
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo/src/network/NetworkSubsystem.ts

/// A type that hosts network subsystems to connect to peers.
///
/// The NetworkSubsystem instance is responsible for setting up and configuring any network providers, and responding to
/// messages from remote peers after the connection has been established. The connection handshake and peer negotiation
/// is
/// the responsibility of the network provider instance.
public struct NetworkSubsystem {
    var adapters: [any NetworkProvider]

    init(adapters: [any NetworkProvider]) {
        self.adapters = adapters
    }

    func send(message _: Data) {}

    // async waits until underlying networks are connected and ready to send and receive messages
    // (aka all networks are connected and "peered")
    func isReady() async -> Bool {
        false
    }

    func whenReady() async {}

    let eventPublisher: PassthroughSubject<NetworkAdapterEvents, Never> = PassthroughSubject()
}

// Collection point for all messages coming in, and going out, of the repository
// it forwards messages from network peers into the relevant places, and forwards messages
// out to peers as needed
//
// In automerge-repo code, it appears to update information on an ephemeral information (
// a sort of middleware) before emitting it upwards.
//
// Expected message types to forward:
//    isSyncMessage(message) ||
//    isEphemeralMessage(message) ||
//    isRequestMessage(message) ||
//    isDocumentUnavailableMessage(message) ||
//    isRemoteSubscriptionControlMessage(message) ||
//    isRemoteHeadsChanged(message)
//

// It also hosts peer to peer network components to allow for browsing and selection of connection,
// as well as potentially an "autoconnect" mode for P2P
