struct WalletStorage {
    jettonBalance: coins
    ownerAddress: address
    minterAddress: address
}

fun WalletStorage.load() {
    return WalletStorage.fromCell(contract.getData());
}

fun WalletStorage.save(self) {
    contract.setData(self.toCell());
}
