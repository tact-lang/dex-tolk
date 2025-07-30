import "errors"
import "math"
import "messages"
import "storage"
import "swap"

type AllowedMessages = NotifyPoolAboutLiquidityDeposit | SwapIn

fun onInternalMessage(in: InMessage) {
    val msg = lazy AllowedMessages.fromSlice(in.body);

    match (msg) {
        NotifyPoolAboutLiquidityDeposit => {}
        SwapIn => {
            var storage = lazy AmmPoolStorage.load();

            var incomingVault: address;
            // TODO: match vs != null
            match (msg.multihopInfo) {
                Cell<MultihopInfo> => {
                    val multihopInfo = msg.multihopInfo.load();

                    // verify if sender is another pool
                    assert (
                        in.senderAddress.isAddressOfAmmPool(
                            multihopInfo.lowerVault,
                            multihopInfo.higherVault,
                            storage.ammPoolCode
                        )
                    ) throw MULTIHOP_SWAP_SENDER_MUST_BE_POOL;

                    // verify that swap chain is consistent
                    assert (
                        storage.isAddressOneOfTheVaults(multihopInfo.outVault)
                    ) throw MULTIHOP_SWAP_OUT_VAULT_MUST_BE_NEXT_POOL_VAULT;

                    incomingVault = multihopInfo.outVault;
                }
                null => {
                    assert (
                        storage.isAddressOneOfTheVaults(in.senderAddress)
                    ) throw SWAP_SENDER_MUST_BE_VAULT;

                    incomingVault = in.senderAddress;
                }
            }

            // at this point we ensured that swap message is
            // indeed from one of the vaults for this pool
            val swap = lazy msg.swap.load();

            if (storage.lowerSideReserve == 0 || storage.higherSideReserve == 0) {
                returnFunds(
                    incomingVault,
                    msg.receiver,
                    msg.amount,
                    swap.parameters.payloadOnFailure
                );
                throw NO_LIQUIDITY_IN_POOL
            }

            if (swap.parameters.timeout > 0 && swap.parameters.timeout < blockchain.now()) {
                returnFunds(
                    incomingVault,
                    msg.receiver,
                    msg.amount,
                    swap.parameters.payloadOnFailure
                );
                throw SWAP_TIMEOUT_EXCEEDED
            }

            val (updatedInReserve, updatedOutReserve, isSwapFromHigherVault) = handleSwap(
                swap,
                msg.amount,
                msg.receiver,
                in.valueCoins,
                incomingVault
            );

            if (isSwapFromHigherVault) {
                storage.higherSideReserve = updatedInReserve;
                storage.lowerSideReserve = updatedOutReserve;
            } else {
                storage.lowerSideReserve = updatedInReserve;
                storage.higherSideReserve = updatedOutReserve;
            }

            storage.save();
        }
    }
}

// get methdos
type VaultsWithReserves = SortedAddressesAndAmounts

get fun vaultsAndReserves(): VaultsWithReserves {
    val storage = lazy AmmPoolStorage.load();
    return {
        lower: storage.lowerVault,
        higher: storage.higherVault,
        lowerAmount: storage.lowerSideReserve,
        higherAmount: storage.higherSideReserve,
    };
}

get fun expectedOut(inVault: address, inAmount: coins) {
    val storage = lazy AmmPoolStorage.load();
    assert (storage.isAddressOneOfTheVaults(inVault)) throw MSG_NOT_FROM_VAULTS;

    val ctx = storage.getSwapContext(inVault);

    val amountInWithAppliedPoolFee = calcAmountInWithPoolFeeApplied(inAmount);
    val updatedInReserveWithAppliedFee = ctx.inReserve + amountInWithAppliedPoolFee;

    val updatedOutReserve = mulDivFloor(
        ctx.outReserve,
        ctx.inReserve,
        updatedInReserveWithAppliedFee
    );

    return ctx.outReserve - updatedOutReserve;
}

get fun expectedIn(inVault: address, exactOutAmount: coins) {
    val storage = lazy AmmPoolStorage.load();
    assert (storage.isAddressOneOfTheVaults(inVault)) throw MSG_NOT_FROM_VAULTS;

    val ctx = storage.getSwapContext(inVault);

    assert (ctx.inReserve != 0 && ctx.outReserve != 0) throw NO_LIQUIDITY_IN_POOL;

    val updatedOutReserve = ctx.outReserve - exactOutAmount;

    assert (updatedOutReserve > 0) throw INSUFFICIENT_RESERVES_FOR_EXACT_OUT_VALUE;

    return calcRequiredAmountInWithPoolFeeApplied(updatedOutReserve, ctx.inReserve, exactOutAmount);
}
