import {
    Address,
    beginCell,
    Cell,
    Contract,
    contractAddress,
    ContractProvider,
    Sender,
    SendMode,
    Slice,
    toNano,
} from "@ton/core"
import {Op} from "./JettonConstants"

function endParse(slice: Slice) {
    if (slice.remainingBits > 0 || slice.remainingRefs > 0) {
        throw new Error("remaining bits in data")
    }
}

export type JettonWalletConfig = {
    ownerAddress: Address
    jettonMasterAddress: Address
}

export function jettonWalletConfigToCell(config: JettonWalletConfig): Cell {
    return beginCell()
        .storeCoins(0) // jetton balance
        .storeAddress(config.ownerAddress)
        .storeAddress(config.jettonMasterAddress)
        .endCell()
}

export function parseJettonWalletData(data: Cell) {
    const sc = data.beginParse()
    const parsed = {
        balance: sc.loadCoins(),
        ownerAddress: sc.loadAddress(),
        jettonMasterAddress: sc.loadAddress(),
    }
    endParse(sc)
    return parsed
}

export class LpJettonWallet implements Contract {
    constructor(
        readonly address: Address,
        readonly init?: {code: Cell; data: Cell},
    ) {}

    static createFromAddress(address: Address) {
        return new LpJettonWallet(address)
    }

    static createFromConfig(config: JettonWalletConfig, code: Cell, workchain = 0) {
        const data = jettonWalletConfigToCell(config)
        const init = {code, data}
        return new LpJettonWallet(contractAddress(workchain, init), init)
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        })
    }

    async getWalletData(provider: ContractProvider) {
        let {stack} = await provider.get("get_wallet_data", [])
        return {
            balance: stack.readBigNumber(),
            owner: stack.readAddress(),
            minter: stack.readAddress(),
            wallet_code: stack.readCell(),
        }
    }
    async getJettonBalance(provider: ContractProvider) {
        let state = await provider.getState()
        if (state.state.type !== "active") {
            return 0n
        }
        let res = await provider.get("get_wallet_data", [])
        return res.stack.readBigNumber()
    }

    static transferMessage(
        jetton_amount: bigint,
        to: Address,
        responseAddress: Address | null,
        customPayload: Cell | null,
        forward_ton_amount: bigint,
        forwardPayload?: Cell | Slice | null,
    ) {
        const byRef = forwardPayload instanceof Cell
        const transferBody = beginCell()
            .storeUint(Op.transfer, 32)
            .storeUint(0, 64) // op, queryId
            .storeCoins(jetton_amount)
            .storeAddress(to)
            .storeAddress(responseAddress)
            .storeMaybeRef(customPayload)
            .storeCoins(forward_ton_amount)
            .storeBit(byRef)

        if (byRef) {
            transferBody.storeRef(forwardPayload)
        } else if (forwardPayload) {
            transferBody.storeSlice(forwardPayload)
        }
        return transferBody.endCell()
    }

    async sendTransfer(
        provider: ContractProvider,
        via: Sender,
        value: bigint,
        jetton_amount: bigint,
        to: Address,
        responseAddress: Address,
        customPayload: Cell | null,
        forward_ton_amount: bigint,
        forwardPayload?: Cell | Slice | null,
    ) {
        await provider.internal(via, {
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: LpJettonWallet.transferMessage(
                jetton_amount,
                to,
                responseAddress,
                customPayload,
                forward_ton_amount,
                forwardPayload,
            ),
            value: value,
        })
    }

    static createLiquidityWithdrawParametersCell(
        minAmountLeft: bigint,
        minAmountRight: bigint,
        timeout: bigint,
        receiver: Address,
        successfulPayload: Cell | null,
    ) {
        return beginCell()
            .storeCoins(minAmountLeft)
            .storeCoins(minAmountRight)
            .storeUint(timeout, 32)
            .storeAddress(receiver)
            .storeMaybeRef(successfulPayload)
            .endCell()
    }

    /*
      burn#595f07bc query_id:uint64 amount:(VarUInteger 16)
                    response_destination:MsgAddress custom_payload:(Maybe ^Cell)
                    = InternalMsgBody;
    */
    static burnMessage(
        jetton_amount: bigint,
        responseAddress: Address | null,
        liqWithdrawalParamsCell: Cell,
    ) {
        return (
            beginCell()
                .storeUint(Op.burn, 32)
                .storeUint(0, 64) // op, queryId
                .storeCoins(jetton_amount)
                // it's AddressNone again, but we actually don't care this time
                // so leave it be
                .storeAddress(responseAddress)
                .storeRef(liqWithdrawalParamsCell)
                .endCell()
        )
    }

    async sendBurn(
        provider: ContractProvider,
        via: Sender,
        value: bigint,
        jetton_amount: bigint,
        responseAddress: Address | null,
        liqWithdrawalParamsCell: Cell,
    ) {
        await provider.internal(via, {
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: LpJettonWallet.burnMessage(
                jetton_amount,
                responseAddress,
                liqWithdrawalParamsCell,
            ),
            value: value,
        })
    }
    /*
      withdraw_tons#107c49ef query_id:uint64 = InternalMsgBody;
    */
    static withdrawTonsMessage() {
        return beginCell()
            .storeUint(0x6d8e5e3c, 32)
            .storeUint(0, 64) // op, queryId
            .endCell()
    }

    async sendWithdrawTons(provider: ContractProvider, via: Sender) {
        await provider.internal(via, {
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: LpJettonWallet.withdrawTonsMessage(),
            value: toNano("0.1"),
        })
    }
    /*
      withdraw_jettons#10 query_id:uint64 wallet:MsgAddressInt amount:Coins = InternalMsgBody;
    */
    static withdrawJettonsMessage(from: Address, amount: bigint) {
        return beginCell()
            .storeUint(0x768a50b2, 32)
            .storeUint(0, 64) // op, queryId
            .storeAddress(from)
            .storeCoins(amount)
            .storeMaybeRef(null)
            .endCell()
    }

    async sendWithdrawJettons(
        provider: ContractProvider,
        via: Sender,
        from: Address,
        amount: bigint,
    ) {
        await provider.internal(via, {
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: LpJettonWallet.withdrawJettonsMessage(from, amount),
            value: toNano("0.1"),
        })
    }
}
