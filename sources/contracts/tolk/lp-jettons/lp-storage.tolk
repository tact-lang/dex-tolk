struct LpWalletStorage {
    jettonBalance: coins
    ownerAddress: address
    minterAddress: address
}

fun LpWalletStorage.load() {
    return LpWalletStorage.fromCell(contract.getData());
}

fun LpWalletStorage.save(self) {
    contract.setData(self.toCell());
}
