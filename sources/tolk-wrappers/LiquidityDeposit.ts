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

export type LiqDepositConfig = {
    lowerVault: Address
    higherVault: Address
    lowerAmount: bigint
    higherAmount: bigint
    lpTokensReceiver: Address
    contractId: bigint
}

export function liquidityDepositConfigToCell(config: LiqDepositConfig): Cell {
    const extraCell = beginCell()
        .storeAddress(config.lpTokensReceiver)
        .storeUint(config.contractId, 64)
        .endCell()

    return beginCell()
        .storeAddress(config.lowerVault)
        .storeAddress(config.higherVault)
        .storeCoins(config.lowerAmount)
        .storeCoins(config.higherAmount)
        .storeRef(extraCell)
        .storeBit(false)
        .storeBit(false)
        .storeMaybeRef(null)
        .storeMaybeRef(null)
        .endCell()
}

export class LiquidityDeposit implements Contract {
    constructor(
        readonly address: Address,
        readonly init?: {code: Cell; data: Cell},
    ) {}

    static createFromAddress(address: Address) {
        return new LiquidityDeposit(address)
    }

    static createFromConfig(config: LiqDepositConfig, code: Cell, workchain = 0) {
        const data = liquidityDepositConfigToCell(config)
        const init = {code, data}
        return new LiquidityDeposit(contractAddress(workchain, init), init)
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        })
    }

    private static parseExtraData = (extra: Cell) => {
        const sc = extra.beginParse()
        const lpTokensReceiver = sc.loadAddress()
        const contractId = sc.loadUint(64)
        return {lpTokensReceiver, contractId}
    }

    private static parseLpAdditionalParams = (params: Cell | null) => {
        if (params === null) {
            return null
        }

        const sc = params.beginParse()
        return {
            minAmountToDeposit: sc.loadCoins(),
            lpTimeout: sc.loadUint(32),
            payloadOnSuccess: sc.loadMaybeRef(),
            payloadOnFailure: sc.loadMaybeRef(),
        }
    }

    async getStorage(provider: ContractProvider) {
        let {stack} = await provider.get("storage", [])

        return {
            lowerVault: stack.readAddress(),
            higherVault: stack.readAddress(),
            lowerAmount: stack.readBigNumber(),
            higherAmount: stack.readBigNumber(),
            extra: LiquidityDeposit.parseExtraData(stack.readCell()),
            isLowerSideFilled: stack.readBoolean(),
            isHigherSideFilled: stack.readBoolean(),
            lowerAdditionalParams: LiquidityDeposit.parseLpAdditionalParams(stack.readCellOpt()),
            higherAdditionalParams: LiquidityDeposit.parseLpAdditionalParams(stack.readCellOpt()),
        }
    }

    async getStatus(provider: ContractProvider) {
        let {stack} = await provider.get("status", [])

        return {
            isLowerSideFilled: stack.readBoolean(),
            isHigherSideFilled: stack.readBoolean(),
        }
    }
}
