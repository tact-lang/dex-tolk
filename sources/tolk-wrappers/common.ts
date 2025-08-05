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
