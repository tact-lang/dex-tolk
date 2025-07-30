import "sharding"
import "storage"

fun calcLpJettonWalletStateInit(
    ownerAddress: address,
    minterAddress: address,
    jettonWalletCode: cell,
): AutoDeployAddress {
    val emptyWalletStorage: WalletStorage = {
        jettonBalance: 0,
        ownerAddress,
        minterAddress,
    };

    return {
        workchain: MY_WORKCHAIN,
        stateInit: { code: jettonWalletCode, data: emptyWalletStorage.toCell() },
        toShard: { fixedPrefixLength: SHARD_DEPTH, closeTo: ownerAddress },
    };
}

fun buildAddressOfLpJettonWallet(
    ownerAddress: address,
    minterAddress: address,
    jettonWalletCode: cell,
) {
    val jwDeployed = calcLpJettonWalletStateInit(ownerAddress, minterAddress, jettonWalletCode);
    return jwDeployed.buildAddress();
}

fun address.isAddressOfLpJettonWallet(
    self,
    ownerAddress: address,
    minterAddress: address,
    jettonWalletCode: cell,
) {
    val jwDeployed = calcLpJettonWalletStateInit(ownerAddress, minterAddress, jettonWalletCode);
    return jwDeployed.addressMatches(self);
}

struct SuccessfulForwardPayload {
    eitherBit: bool
    lowerSuccessPayload: cell?
    higherSuccessPayload: cell?
}

fun createSuccessfulForwardPayload(lowerSuccessPayload: cell?, higherSuccessPayload: cell?) {
    return SuccessfulForwardPayload {
        eitherBit: false,
        lowerSuccessPayload,
        higherSuccessPayload,
    }
        .toCell()
        .beginParse();
}
