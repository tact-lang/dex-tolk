import "lp-storage"

type ForwardPayloadRemainder = RemainingBitsAndRefs

struct (0x0f8a7ea5) AskToTransfer {
    queryId: uint64
    jettonAmount: coins
    transferRecipient: address
    sendExcessesTo: address
    customPayload: cell?
    forwardTonAmount: coins
    forwardPayload: ForwardPayloadRemainder
}

struct (0x7362d09c) TransferNotificationForRecipient {
    queryId: uint64
    jettonAmount: coins
    transferInitiator: address
    forwardPayload: ForwardPayloadRemainder
}

struct (0x178d4519) LpJettonTransferInternal {
    queryId: uint64
    jettonAmount: coins
    transferInitiator: address
    sendAllTonsInNotifyFlag: bool
    sendExcessesTo: address
    forwardTonAmount: coins
    forwardPayload: ForwardPayloadRemainder
}

struct (0xd53276db) ReturnExcessesBack {
    queryId: uint64
}

struct LiquidityWithdrawParameters {
    lowerAmountMin: coins
    higherAmountMin: coins
    timeout: uint32
    receiver: address
    liquidityWithdrawPayload: cell?
}

struct (0x595f07bc) LPWithdrawViaJettonBurn {
    queryId: uint64
    jettonAmount: coins
    sendExcessesTo: address
    parameters: Cell<LiquidityWithdrawParameters>
}

struct (0x7bdd97de) LiquidityWithdrawViaBurnNotification {
    queryId: uint64
    jettonAmount: coins
    burnInitiator: address
    sendExcessesTo: address
    parameters: Cell<LiquidityWithdrawParameters>
}

struct (0x2c76b973) RequestWalletAddress {
    queryId: uint64
    ownerAddress: address
    includeOwnerAddress: bool
}

struct (0xd1735400) ResponseWalletAddress {
    queryId: uint64
    jettonWalletAddress: address
    ownerAddress: Cell<address>?
}

// "forward payload" is TL/B `(Either Cell ^Cell)`;
// we want to test, that if ^Cell, no other data exists in a slice
fun ForwardPayloadRemainder.checkIsCorrectTLBEither(self) {
    var mutableCopy = self;
    if (mutableCopy.loadMaybeRef() != null) {
        // throw "cell underflow" if there is data besides a ref
        mutableCopy.assertEnd();
    }
}
