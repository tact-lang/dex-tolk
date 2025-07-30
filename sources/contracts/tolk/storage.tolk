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
}

fun calcAmmPoolStateInit(lowerVault: address, higherVault: address, ammPoolCode: cell): AutoDeployAddress {
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
            }
                .toCell(),
        },
    };
}

fun address.isAddressOfAmmPool(self, lowerVault: address, higherVault: address, ammPoolCode: cell) {
    val ammPool = calcAmmPoolStateInit(lowerVault, higherVault, ammPoolCode);
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

fun calcLpDepositStateInit(
    lowerVault: address,
    higherVault: address,
    lowerAmount: coins,
    higherAmount: coins,
    lpTokensReceiver: address,
    contractId: uint64,
    liquidityDepositCode: cell,
): AutoDeployAddress {
    return {
        workchain: BASECHAIN,
        stateInit: {
            code: liquidityDepositCode,
            data: LiquidityDepositStorage {
                lowerVault,
                higherVault,
                lowerAmount,
                higherAmount,
                extra: LiquidityDepositExtraFields { contractId, lpTokensReceiver }.toCell(),
                isHigherSideFilled: false,
                isLowerSideFilled: false,
                higherAdditionalParams: null,
                lowerAdditionalParams: null,
            }
                .toCell(),
        },
    };
}
