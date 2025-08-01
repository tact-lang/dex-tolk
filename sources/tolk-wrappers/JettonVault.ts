import {
    Address,
    beginCell,
    Cell,
    Contract,
    contractAddress,
    ContractProvider,
    Sender,
    SendMode,
} from "@ton/core"
import {Op} from "./DexConstants"
import {storeLiquidityDepositDestination, storeLpAdditionalParams} from "./common"

export type JettonVaultConfig = {
    jettonMaster: Address
    ammPoolCode: Cell
    liquidityDepositContractCode: Cell
    jettonWalletCode: Cell
}

export function jettonVaultConfigToCell(config: JettonVaultConfig): Cell {
    return beginCell()
        .storeAddress(config.jettonMaster)
        .storeAddress(null)
        .storeRef(config.ammPoolCode)
        .storeRef(config.liquidityDepositContractCode)
        .storeRef(config.jettonWalletCode)
        .endCell()
}

export class JettonVault implements Contract {
    constructor(
        readonly address: Address,
        readonly init?: {code: Cell; data: Cell},
    ) {}

    static createFromAddress(address: Address) {
        return new JettonVault(address)
    }

    static createFromConfig(config: JettonVaultConfig, code: Cell, workchain = 0) {
        const data = jettonVaultConfigToCell(config)
        const init = {code, data}
        return new JettonVault(contractAddress(workchain, init), init)
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        })
    }

    static createJettonVaultLiquidityDepositBody(
        // TODO: either structs for typescript
        liquidityDepositContractAddress: Address,
        amount: bigint,
        payloadOnSuccess: Cell | null,
        payloadOnFailure: Cell | null,
        minAmountToDeposit: bigint,
        lpTimeout: bigint,
        lpTokensReceiver: Address | null,
        liquidityDepositContractData: {
            otherVaultAddress: Address
            otherAmount: bigint
            id: bigint
        } | null,
    ): Cell {
        return beginCell()
            .storeUint(Op.AddLiquidityPartTon, 32)
            .storeCoins(amount)
            .store(
                storeLiquidityDepositDestination(
                    liquidityDepositContractAddress,
                    liquidityDepositContractData,
                ),
            )
            .store(
                storeLpAdditionalParams(
                    payloadOnSuccess,
                    payloadOnFailure,
                    minAmountToDeposit,
                    lpTimeout,
                ),
            )
            .storeAddress(lpTokensReceiver)
            .endCell()
    }
}
