protocol SyncThing {
    func peers() -> [PEER_ID]
    func removePeer(peer: PEER_ID)
    func addPeer(peer: PEER_ID)
    func addDoc(doc: DocumentId)
    func removeDoc(doc: DocumentId)
    func receiveMsg(msg: SyncV1)
}

// CollectionSynchronizer
//  - multiple DocumentSynchronizers
