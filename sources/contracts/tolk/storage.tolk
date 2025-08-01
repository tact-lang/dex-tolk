import "messages"

// amm pool storage
struct AmmPoolStorage {
    lowerVault: address
    higherVault: address
    // amounts of assets in coins
    lowerSideReserve: coins
    higherSideReserve: coins
    // lp tokens fields
    totalSupply: coins
    jettonContent: cell?
    // code for on-chain auth
    ammPoolCode: cell
    liquidityDepositCode: cell
    jettonWalletCode: cell
}

fun AmmPoolStorage.load() {
    return AmmPoolStorage.fromCell(contract.getData());
}

fun AmmPoolStorage.save(self) {
    contract.setData(self.toCell());
}

@pure
fun AmmPoolStorage.isAddressOneOfTheVaults(self, addr: address) {
    return self.lowerVault == addr || self.higherVault == addr;
}

fun calcAmmPoolStateInit(
    lowerVault: address,
    higherVault: address,
    ammPoolCode: cell,
    liquidityDepositCode: cell,
    jettonWalletCode: cell,
): AutoDeployAddress {
    return {
        workchain: BASECHAIN,
        stateInit: {
            code: ammPoolCode,
            data: AmmPoolStorage {
                lowerVault,
                higherVault,
                lowerSideReserve: 0,
                higherSideReserve: 0,
                totalSupply: 0,
                jettonContent: null,
                ammPoolCode,
                liquidityDepositCode,
                jettonWalletCode,
            }
                .toCell(),
        },
    };
}

fun address.isAddressOfAmmPool(
    self,
    lowerVault: address,
    higherVault: address,
    ammPoolCode: cell,
    liquidityDepositCode: cell,
    jettonWalletCode: cell,
) {
    val ammPool = calcAmmPoolStateInit(
        lowerVault,
        higherVault,
        ammPoolCode,
        liquidityDepositCode,
        jettonWalletCode
    );
    return ammPool.addressMatches(self);
}

// liquidity deposit contract storage
struct LiquidityDepositStorage {
    lowerVault: address
    higherVault: address
    // amounts for this instance of lp provisioning
    lowerAmount: coins
    higherAmount: coins
    // extra ref with remaining fields
    extra: Cell<LiquidityDepositExtraFields>
    isLowerSideFilled: bool
    isHigherSideFilled: bool
    lowerAdditionalParams: Cell<LpAdditionalParams>?
    higherAdditionalParams: Cell<LpAdditionalParams>?
}

type EitherLpExtraFields = Cell<LiquidityDepositExtraFields> | (address, uint64)

fun calcLiquidityDepositStateInit(
    lowerVault: address,
    higherVault: address,
    lowerAmount: coins,
    higherAmount: coins,
    lpExtraFields: EitherLpExtraFields,
    liquidityDepositCode: cell,
): AutoDeployAddress {
    val extra = match (lpExtraFields) {
        Cell<LiquidityDepositExtraFields> => lpExtraFields,
        (address, uint64) => LiquidityDepositExtraFields {
            lpTokensReceiver: lpExtraFields.0,
            contractId: lpExtraFields.1,
        }
            .toCell(),
    };

    return {
        workchain: BASECHAIN,
        stateInit: {
            code: liquidityDepositCode,
            data: LiquidityDepositStorage {
                lowerVault,
                higherVault,
                lowerAmount,
                higherAmount,
                extra,
                isHigherSideFilled: false,
                isLowerSideFilled: false,
                higherAdditionalParams: null,
                lowerAdditionalParams: null,
            }
                .toCell(),
        },
    };
}

fun address.isAddressOfLiquidityDeposit(
    self,
    lowerVault: address,
    higherVault: address,
    lowerAmount: coins,
    higherAmount: coins,
    lpExtraFields: EitherLpExtraFields,
    liquidityDepositCode: cell,
) {
    val liquidityDeposit = calcLiquidityDepositStateInit(
        lowerVault,
        higherVault,
        lowerAmount,
        higherAmount,
        lpExtraFields,
        liquidityDepositCode
    );
    return liquidityDeposit.addressMatches(self);
}
