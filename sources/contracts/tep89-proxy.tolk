import "storage"
import "errors"
import "messages"

// Proxy for TEP-89 wallet discovery process
// Handles interaction with Jetton Master and result delivery
fun onInternalMessage(in: InMessage) {
    var msg = lazy AllowedMessagesForProxy.fromSlice(in.body);
    match (msg) {
        TakeWalletAddress => {
            var storage = lazy ProxyStorage.load();
            assert (in.senderAddress == storage.minter) throw SENDER_IS_NOT_THE_DISCOVERY_REQUESTER;
            // Return discovery result to requester
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

            msg.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_DESTROY);
        }
        // will be triggered on deployment
        else => {
            var storage = lazy ProxyStorage.load();
            assert (in.senderAddress == storage.discoveryRequester) throw SENDER_IS_NOT_THE_MINTER;
            val msg = createMessage({
                dest: storage.minter,
                bounce: true, // So we can save some tons (we won't pay storage fees for JettonMaster)
                value: 0,
                body: ProvideWalletAddress {
                    queryId: 0,
                    ownerAddress: storage.discoveryRequester,
                    // We could ask to provide address, but it is cheaper to store it in data
                    includeAddress: false, 
                },
            });

            msg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }
    }
}

fun onBouncedMessage(in: InMessageBounced) {
    // handle failed discovery request
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
