import {Address} from "@ton/core"
import {LiquidityDeposit} from "../tolk-wrappers/LiquidityDeposit"
import {TonVault} from "../tolk-wrappers/TonVault"
import {compileAll} from "./compile"
import {AmmPool} from "../tolk-wrappers/AmmPool"

const compiledDex = compileAll()

export const createTonVaultContract = async () => {
    const dex = await compiledDex

    return TonVault.createFromConfig(
        {
            ammPoolCode: dex["amm-pool"],
            liquidityDepositContractCode: dex["liquidity-deposit"],
            jettonWalletCode: dex["lp-jetton-wallet"],
        },
        dex["ton-vault"],
    )
}

export const createLiquidityDepositContract = async (
    contractId: bigint,
    lpTokensReceiver: Address,
    lowerVault: Address,
    higherVault: Address,
    lowerAmount: bigint,
    higherAmount: bigint,
) => {
    const dex = await compiledDex

    return LiquidityDeposit.createFromConfig(
        {
            lowerVault,
            higherVault,
            lowerAmount,
            higherAmount,
            lpTokensReceiver,
            contractId,
        },
        dex["liquidity-deposit"],
    )
}

export const createAmmPoolContract = async (lowerVault: Address, higherVault: Address) => {
    const dex = await compiledDex

    return AmmPool.createFromConfig(
        {
            lowerVault,
            higherVault,
            ammPoolCode: dex["amm-pool"],
            liquidityDepositContractCode: dex["liquidity-deposit"],
            jettonWalletCode: dex["lp-jetton-wallet"],
        },
        dex["amm-pool"],
    )
}
