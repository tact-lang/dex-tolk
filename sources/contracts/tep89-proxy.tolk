import "storage"

struct (0x7a1267fd) TEP89DiscoveryResult {
    discoveryId: uint64
    expectedJettonWallet: address
    actualJettonWallet: address?
    action: cell
}

struct (0xd1735400) TakeWalletAddress {
    queryId: uint64
    jettonWalletAddress: address?
    ownerAddress: Cell<address>?
}

struct (0x2c76b973) ProvideWalletAddress {
    queryId: uint64
    ownerAddress: address
    includeAddress: bool
}

type AllowedMessagesForProxy = TakeWalletAddress

fun onInternalMessage(in: InMessage) {
    var msg = lazy AllowedMessagesForProxy.fromSlice(in.body);
    match (msg) {
        TakeWalletAddress => {
            var storage = lazy ProxyStorage.load();
            assert (in.senderAddress == storage.minter) throw 1543;
            val msg = createMessage({
                dest: storage.discoveryRequester,
                bounce: false,
                value: 0,
                body: TEP89DiscoveryResult {
                    discoveryId: storage.discoveryId,
                    expectedJettonWallet: storage.expectedJettonWallet,
                    actualJettonWallet: msg.jettonWalletAddress,
                    action: storage.action,
                },
            });

            msg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }

        else => {
            var storage = lazy ProxyStorage.load();
            assert (in.senderAddress == storage.discoveryRequester) throw 11580;
            val msg = createMessage({
                dest: storage.minter,
                bounce: true,
                value: 0,
                body: ProvideWalletAddress {
                    queryId: 0,
                    ownerAddress: storage.discoveryRequester,
                    includeAddress: false,
                },
            });

            msg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }
    }
}

fun onBouncedMessage(in: InMessageBounced) {
    in.bouncedBody.skipBouncedPrefix();

    val msg = lazy ProvideWalletAddress.fromSlice(in.bouncedBody);
    var storage = lazy ProxyStorage.load();
    val bounceMsg = createMessage({
        dest: storage.discoveryRequester,
        bounce: false,
        value: 0,
        body: TEP89DiscoveryResult {
            discoveryId: storage.discoveryId,
            expectedJettonWallet: storage.expectedJettonWallet,
            actualJettonWallet: null,
            action: storage.action,
        },
    });

    bounceMsg.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_DESTROY);
}

get fun checker(): bool {
    return true;
}
