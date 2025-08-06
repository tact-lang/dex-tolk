import {
    Address,
    beginCell,
    Cell,
    Contract,
    contractAddress,
    ContractProvider,
    Sender,
    SendMode,
    toNano,
} from "@ton/core"
import {Op} from "./lp-jettons/JettonConstants"

export type AmmPoolConfig = {
    lowerVault: Address
    higherVault: Address
    ammPoolCode: Cell
    liquidityDepositContractCode: Cell
    jettonWalletCode: Cell
}

export function ammPoolConfigToCell(config: AmmPoolConfig): Cell {
    return beginCell()
        .storeAddress(config.lowerVault)
        .storeAddress(config.higherVault)
        .storeCoins(0)
        .storeCoins(0)
        .storeCoins(0)
        .storeMaybeRef(null)
        .storeRef(config.ammPoolCode)
        .storeRef(config.liquidityDepositContractCode)
        .storeRef(config.jettonWalletCode)
        .endCell()
}

export class AmmPool implements Contract {
    constructor(
        readonly address: Address,
        readonly init?: {code: Cell; data: Cell},
    ) {}

    static createFromAddress(address: Address) {
        return new AmmPool(address)
    }

    static createFromConfig(config: AmmPoolConfig, code: Cell, workchain = 0) {
        const data = ammPoolConfigToCell(config)
        const init = {code, data}
        return new AmmPool(contractAddress(workchain, init), init)
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        })
    }

    /* provide_wallet_address#2c76b973 query_id:uint64 owner_address:MsgAddress include_address:Bool = InternalMsgBody;
     */
    static discoveryMessage(owner: Address, includeAddress: boolean) {
        return beginCell()
            .storeUint(Op.provide_wallet_address, 32)
            .storeUint(0, 64) // op, queryId
            .storeAddress(owner)
            .storeBit(includeAddress)
            .endCell()
    }

    async sendDiscovery(
        provider: ContractProvider,
        via: Sender,
        owner: Address,
        includeAddress: boolean,
        value: bigint = toNano("0.1"),
    ) {
        await provider.internal(via, {
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: AmmPool.discoveryMessage(owner, includeAddress),
            value: value,
        })
    }

    static createLiquidityWithdrawalPayload(
        lowerAmountMin: bigint,
        higherAmountMin: bigint,
        timeout: number,
        receiver: Address,
        liquidityWithdrawPayload: Cell | null,
    ): Cell {
        return beginCell()
            .storeCoins(lowerAmountMin)
            .storeCoins(higherAmountMin)
            .storeUint(timeout, 32)
            .storeAddress(receiver)
            .storeMaybeRef(liquidityWithdrawPayload)
            .endCell()
    }

    async getVaultsAndReserves(provider: ContractProvider) {
        let {stack} = await provider.get("vaultsAndReserves", [])

        return {
            lowerVault: stack.readAddress(),
            higherVault: stack.readAddress(),
            lowerAmount: stack.readBigNumber(),
            higherAmount: stack.readBigNumber(),
        }
    }

    async getExpectedOut(provider: ContractProvider, inVault: Address, inAmount: bigint) {
        let {stack} = await provider.get("expectedOut", [
            {
                type: "slice",
                cell: beginCell().storeAddress(inVault).endCell(),
            },
            {
                type: "int",
                value: inAmount,
            },
        ])

        return stack.readBigNumber()
    }

    async getExpectedIn(provider: ContractProvider, inVault: Address, exactOutAmount: bigint) {
        let {stack} = await provider.get("expectedIn", [
            {
                type: "slice",
                cell: beginCell().storeAddress(inVault).endCell(),
            },
            {
                type: "int",
                value: exactOutAmount,
            },
        ])

        return stack.readBigNumber()
    }

    async getWalletAddress(provider: ContractProvider, owner: Address): Promise<Address> {
        const res = await provider.get("get_wallet_address", [
            {
                type: "slice",
                cell: beginCell().storeAddress(owner).endCell(),
            },
        ])

        return res.stack.readAddress()
    }

    async getJettonData(provider: ContractProvider) {
        let res = await provider.get("get_jetton_data", [])

        let totalSupply = res.stack.readBigNumber()
        let mintable = res.stack.readBoolean()
        let adminAddress = res.stack.readAddressOpt()
        let content = res.stack.readCell()
        let walletCode = res.stack.readCell()

        return {
            totalSupply,
            mintable,
            adminAddress,
            content,
            walletCode,
        }
    }
}
