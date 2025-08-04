import {
    Address,
    beginCell,
    Builder,
    Cell,
    Contract,
    contractAddress,
    ContractProvider,
    Sender,
    SendMode,
    Slice,
} from "@ton/core"
import {Op} from "./DexConstants"
import {storeLiquidityDepositDestination, storeLpAdditionalParams} from "./common"
import "./ExtendedBuilder"

export type JettonVaultConfig = {
    jettonMaster: Address
    ammPoolCode: Cell
    liquidityDepositContractCode: Cell
    jettonWalletCode: Cell
}

export type NoProof = {
    proofType: typeof JettonVault.PROOF_NO_PROOF_ATTACHED
}

export type MinterDiscoveryProof = {
    proofType: typeof JettonVault.MINTER_DISCOVERY_PROOF
}

export type OnchainGetterProof = {
    proofType: typeof JettonVault.ONCHAIN_GETTER_PROOF
    code: Cell
    data: Cell
}

export type StateProof = {
    proofType: typeof JettonVault.PROOF_STATE_TO_THE_BLOCK
    mcBlockSeqno: bigint
    shardBitLen: bigint
    mcBlockHeaderProof: Cell
    shardBlockHeaderProof: Cell
    shardChainStateProof: Cell
}

export type Proof = NoProof | MinterDiscoveryProof | OnchainGetterProof | StateProof

export function jettonVaultConfigToCell(config: JettonVaultConfig): Cell {
    return beginCell()
        .storeAddress(config.jettonMaster)
        .storeMaybeInternalAddress(null)
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

    static readonly PROOF_NO_PROOF_ATTACHED = 0n
    static readonly MINTER_DISCOVERY_PROOF = 1n
    static readonly ONCHAIN_GETTER_PROOF = 2n
    static readonly PROOF_STATE_TO_THE_BLOCK = 3n

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

    async getJettonVaultInfo(provider: ContractProvider) {
        let res = await provider.get("storage", [])

        return {
            jettonMaster: res.stack.readAddress(),
            // TODO: check if this reads Maybe<InternalAddress> as null | address,
            // not Address | AddressNone
            jettonWallet: res.stack.readAddressOpt(),
        }
    }

    private static storeProof(proof: Proof) {
        return (b: Builder) => {
            b.storeUint(proof.proofType, 4)

            switch (proof.proofType) {
                case JettonVault.PROOF_NO_PROOF_ATTACHED:
                    break
                case JettonVault.MINTER_DISCOVERY_PROOF:
                    break
                case JettonVault.ONCHAIN_GETTER_PROOF:
                    b.storeMaybeUint(null, 5)
                        .storeMaybeUint(null, 2)
                        .storeMaybeRef(proof.code)
                        .storeMaybeRef(proof.data)
                        .storeMaybeRef(null)
                    break
                case JettonVault.PROOF_STATE_TO_THE_BLOCK:
                    // TODO: do
                    break
                default:
                    throw new Error("Unknown proof type")
            }
        }
    }

    static createJettonVaultLiquidityDepositBody(
        // TODO: either structs for typescript
        liquidityDepositContractAddress: Address,
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
            .storeUint(Op.AddLiquidityPartJetton, 32)
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

    static createJettonVaultNotificationPayload(action: Cell, proof: Proof): Slice {
        return (
            beginCell()
                // actually ShardedJetton wrappers handle either bit themselves
                // .storeBit(0)
                .storeRef(action)
                .store(JettonVault.storeProof(proof))
                .endCell()
                .asSlice()
        )
    }
}
