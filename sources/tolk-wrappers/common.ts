import {Address, beginCell, Builder, Cell} from "@ton/core"

export const storeLiquidityDepositDestination = (
    LPContract: Address,
    liquidityDepositContractData: {
        otherVaultAddress: Address
        otherAmount: bigint
        id: bigint
    } | null,
) => {
    return (builder: Builder) => {
        if (liquidityDepositContractData === null) {
            builder.storeBit(1).storeAddress(LPContract)
        } else {
            builder
                .storeBit(0)
                .storeAddress(liquidityDepositContractData.otherVaultAddress)
                .storeCoins(liquidityDepositContractData.otherAmount)
                .storeUint(liquidityDepositContractData.id, 64)
        }
    }
}

export const storeLpAdditionalParams = (
    payloadOnSuccess: Cell | null = null,
    payloadOnFailure: Cell | null = null,
    minAmountToDeposit: bigint = 0n,
    lpTimeout: bigint = BigInt(Math.ceil(Date.now() / 1000) + 5 * 60),
) => {
    return (builder: Builder) => {
        const additionalParamsCell = beginCell()
            .storeCoins(minAmountToDeposit)
            .storeUint(lpTimeout, 32)
            .storeMaybeRef(payloadOnSuccess)
            .storeMaybeRef(payloadOnFailure)
            .endCell()

        builder.storeRef(additionalParamsCell)
    }
}

export type SwapStep = {
    pool: Address
    minAmountOut: bigint
    nextStep: SwapStep | null
}

export type ExactInSwap = {
    type: "exact-in"
    minAmountOut: bigint
    nextStep: SwapStep | null
}

export type ExactOutSwap = {
    type: "exact-out"
    cashbackAddress: Address | null
    exactOutAmount: bigint
}

export type SwapInfo = ExactInSwap | ExactOutSwap

export type SwapParameters = {
    timeout: bigint
    payloadOnSuccess: Cell | null
    payloadOnFailure: Cell | null
}

export type Swap = {
    swapInfo: SwapInfo
    parameters: SwapParameters
}

export type SwapRequest = {
    pool: Address
    receiver: Address | null
    swap: Swap
}

export const storeNextStep = (step: SwapStep) => {
    return (builder: Builder) => {
        builder.storeAddress(step.pool).storeCoins(step.minAmountOut)

        if (step.nextStep === null) {
            builder.storeMaybeRef(null)
        } else {
            builder.storeMaybeRef(beginCell().store(storeNextStep(step.nextStep)).endCell())
        }
    }
}

export const storeSwapInfo = (info: SwapInfo) => {
    return (builder: Builder) => {
        if (info.type === "exact-in") {
            builder.storeBit(true).storeCoins(info.minAmountOut)

            if (info.nextStep === null) {
                builder.storeMaybeRef(null)
            } else {
                builder.storeMaybeRef(beginCell().store(storeNextStep(info.nextStep)).endCell())
            }
        } else {
            builder
                .storeBit(false)
                .storeMaybeInternalAddress(info.cashbackAddress)
                .storeCoins(info.exactOutAmount)
        }
    }
}

export const storeSwapParams = (params: SwapParameters) => {
    return (builder: Builder) => {
        builder
            .storeUint(params.timeout, 32)
            .storeMaybeRef(params.payloadOnSuccess)
            .storeMaybeRef(params.payloadOnFailure)
    }
}

export const storeSwap = (swap: Swap) => {
    return (builder: Builder) => {
        builder.store(storeSwapInfo(swap.swapInfo)).store(storeSwapParams(swap.parameters))
    }
}

export const storeSwapRequest = (request: SwapRequest) => {
    return (builder: Builder) => {
        builder
            .storeAddress(request.pool)
            .storeMaybeInternalAddress(request.receiver)
            .store(storeSwap(request.swap))
    }
}

// extending core Builder to correctly store optional addresses
declare module "@ton/core" {
    interface Builder {
        storeMaybeInternalAddress(address: Address | null): Builder
    }
}

// we want to store Maybe<InternalAddress> as maybe zero, not as AddressNone
Builder.prototype.storeMaybeInternalAddress = function (address: Address | null): Builder {
    if (address === null) {
        return this.storeBit(0)
    }

    return this.storeBit(1).storeAddress(address)
}
