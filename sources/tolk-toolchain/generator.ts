import {Address, Cell} from "@ton/core"
import {LiquidityDeposit} from "../tolk-wrappers/LiquidityDeposit"
import {TonVault} from "../tolk-wrappers/TonVault"
import {compileAll} from "./compile"
import {AmmPool} from "../tolk-wrappers/AmmPool"
import {JettonVault} from "../tolk-wrappers/JettonVault"
import {
    JettonMinterContent,
    ShardedJettonMinter,
} from "../tolk-wrappers/sharded-jettons/ShardedJettonMinter"
import {LpJettonWallet} from "../tolk-wrappers/lp-jettons/LpJettonWallet"

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
    lowerVault: Address,
    higherVault: Address,
    lowerAmount: bigint,
    higherAmount: bigint,
    lpTokensReceiver: Address,
    contractId: bigint,
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

export const createJettonVaultContract = async (jettonMaster: Address) => {
    const dex = await compiledDex

    return JettonVault.createFromConfig(
        {
            jettonMaster,
            ammPoolCode: dex["amm-pool"],
            liquidityDepositContractCode: dex["liquidity-deposit"],
            jettonWalletCode: dex["lp-jetton-wallet"],
        },
        dex["jetton-vault"],
    )
}

export const createShardedJettonMinterContract = async (
    admin: Address,
    jettonContent: Cell | JettonMinterContent,
) => {
    const dex = await compiledDex

    return ShardedJettonMinter.createFromConfig(
        {
            admin,
            jetton_content: jettonContent,
            wallet_code: dex["sharded-jetton-wallet"],
        },
        dex["sharded-jetton-minter"],
    )
}

export const createLpJettonWalletContract = async (
    jettonMasterAddress: Address,
    ownerAddress: Address,
) => {
    const dex = await compiledDex

    return LpJettonWallet.createFromConfig(
        {
            jettonMasterAddress,
            ownerAddress,
        },
        dex["lp-jetton-wallet"],
    )
}
