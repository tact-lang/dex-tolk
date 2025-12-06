import {
    Address,
    beginCell,
    Cell,
    Contract,
    ContractABI,
    contractAddress,
    ContractProvider,
    Sender,
    SendMode,
} from "@ton/core"

export type TEP89ProxyConfig = {
    discoveryId: number
    jettonMaster: Address
    expectedJW: Address
    discoveryRequester: Address
    action: Cell
}

export function TEP89ProxyConfigToCell(config: TEP89ProxyConfig): Cell {
    return beginCell()
        .storeUint(config.discoveryId, 64)
        .storeAddress(config.jettonMaster)
        .storeAddress(config.expectedJW)
        .storeAddress(config.discoveryRequester)
        .storeRef(beginCell().endCell())
        .endCell()
}

export class TEP89Proxy implements Contract {
    abi: ContractABI = {name: "TEP89Proxy"}

    constructor(
        readonly address: Address,
        readonly init?: {code: Cell; data: Cell},
    ) {}

    static createFromAddress(address: Address) {
        return new TEP89Proxy(address)
    }

    static createFromConfig(config: TEP89ProxyConfig, code: Cell, workchain = 0) {
        const data = TEP89ProxyConfigToCell(config)
        const init = {code, data}
        return new TEP89Proxy(contractAddress(workchain, init), init)
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        })
    }
}
