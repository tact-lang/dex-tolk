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
import {DexOpcodes} from "./DexConstants"
import {storeLiquidityDepositDestination, storeLpAdditionalParams} from "./common"

export type TonVaultConfig = {
    ammPoolCode: Cell
    liquidityDepositContractCode: Cell
    jettonWalletCode: Cell
}

export function tonVaultConfigToCell(config: TonVaultConfig): Cell {
    return beginCell()
        .storeRef(config.ammPoolCode)
        .storeRef(config.liquidityDepositContractCode)
        .storeRef(config.jettonWalletCode)
        .endCell()
}

export class TonVault implements Contract {
    constructor(
        readonly address: Address,
        readonly init?: {code: Cell; data: Cell},
    ) {}

    static createFromAddress(address: Address) {
        return new TonVault(address)
    }

    static createFromConfig(config: TonVaultConfig, code: Cell, workchain = 0) {
        const data = tonVaultConfigToCell(config)
        const init = {code, data}
        return new TonVault(contractAddress(workchain, init), init)
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        })
    }

    static createTonVaultLiquidityDepositBody(
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
            .storeUint(DexOpcodes.AddLiquidityPartTon, 32)
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
            .storeMaybeInternalAddress(lpTokensReceiver)
            .endCell()
    }
}
