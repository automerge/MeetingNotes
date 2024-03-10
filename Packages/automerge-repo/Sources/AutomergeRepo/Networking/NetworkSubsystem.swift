import AsyncAlgorithms
import struct Foundation.Data

// riff
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo/src/network/NetworkSubsystem.ts

/// A type that hosts network subsystems to connect to peers.
///
/// The NetworkSubsystem instance is responsible for setting up and configuring any network providers, and responding to
/// messages from remote peers after the connection has been established. The connection handshake and peer negotiation
/// is
/// the responsibility of the network provider instance.
public actor NetworkSubsystem {
    var adapters: [any NetworkProvider]
    let combinedNetworkEvents: AsyncChannel<NetworkAdapterEvents>
    var _backgroundNetworkReaderTasks: [Task<Void, Never>] = []
    init(adapters: [any NetworkProvider]) async {
        self.adapters = adapters
        combinedNetworkEvents = AsyncChannel()
        for adapter in adapters {
            await connectAdapter(adapter: adapter)
        }
    }

    func connectAdapter(adapter: any NetworkProvider) async {
        _backgroundNetworkReaderTasks.append(
            // for each network adapter, read it's channel of
            // network event messages and "forward" them upstream
            // to the Repo (or whomever is reading the NetworkSubsystem's
            // combinedNetworkEvents channel.
            Task {
                for await msg in adapter.events {
                    await self.combinedNetworkEvents.send(msg)
                }
            }
        )
    }

    func send(message: SyncV1Msg) async {
        // send any message to ALL adapters (is this right?)
        for n in adapters {
            await n.send(message: message)
        }
    }

    // async waits until underlying networks are connected and ready to send and receive messages
    // (aka all networks are connected and "peered")
    func isReady() async -> Bool {
        for adapter in adapters {
            if await !adapter.ready() {
                return false
            }
        }
        return true
    }

    func allNetworksReady() async throws {
        var currentlyReady = await self.isReady()
        while currentlyReady != true {
            try await Task.sleep(for: .milliseconds(500))
            currentlyReady = await self.isReady()
        }
    }

    // combine version
    // import class Combine.PassthroughSubject
//    let eventPublisher: PassthroughSubject<NetworkAdapterEvents, Never> = PassthroughSubject()
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
