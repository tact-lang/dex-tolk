import "errors"
import "math"
import "messages"
import "storage"
import "swap"

struct LiquidityProvisioningResult {
    updatedLowerReserve: coins
    updatedHigherReserve: coins
    lpTokensToMint: coins
}

@pure
@inline
fun calcLpTokensAmountAfterFirstDeposit(
    lowerAmount: coins,
    higherAmount: coins,
    lowerSideReserve: coins,
    higherSideReserve: coins,
    totalSupply: coins,
) {
    return min(
        mulDivFloor(lowerAmount, totalSupply, lowerSideReserve - lowerAmount),
        mulDivFloor(higherAmount, totalSupply, higherSideReserve - higherAmount)
    );
}

@pure
fun handleReservesUpdate(
    lowerAmount: coins,
    higherAmount: coins,
    lowerAdditionalParams: LpAdditionalParams,
    higherAdditionalParams: LpAdditionalParams,
    lpTokensReceiver: address,
    inValue: coins,
): LiquidityProvisioningResult {
    val storage = lazy AmmPoolStorage.load();

    if (storage.lowerSideReserve == 0) {
        return {
            updatedLowerReserve: lowerAmount,
            updatedHigherReserve: higherAmount,
            lpTokensToMint: sqrt(lowerAmount * higherAmount),
        };
    }

    // [lower, higher] - reserves before current liquidity provisioning
    // [lowerAmount, higherAmount] - incoming liquidity
    // 
    // constant product formula fixes invariant:
    // 'lower * higher = k'
    // 
    // we want 'lower/higher == lowerAmount/higherAmount'
    // and for that we need to balance either of sides
    if (higherAmount * storage.lowerSideReserve > storage.higherSideReserve * lowerAmount) {
        // 'balancedHigherAmount = lowerAmount * higher / lower'
        val balancedHigherAmount: coins = mulDivFloor(
            lowerAmount,
            storage.higherSideReserve,
            storage.lowerSideReserve
        );

        if (balancedHigherAmount < higherAdditionalParams.minAmountToDeposit) {
            // TODO: fail lp
            throw LIQUIDITY_PROVISIONING_SLIPPAGE_FAILED
        }

        // refund higher lp excesses if we received more than we can accept
        if (higherAmount > balancedHigherAmount) {
            val liquidityExcessesRefundMsg = createMessage({
                body: PayoutFromPool {
                    otherVault: storage.lowerVault,
                    amount: higherAmount - balancedHigherAmount,
                    receiver: lpTokensReceiver,
                    payloadToForward: higherAdditionalParams.payloadOnSuccess,
                },
                bounce: false,
                dest: storage.higherVault,
                value: getHalfOfTheMsgValue(inValue),
            });

            liquidityExcessesRefundMsg.send(SEND_MODE_REGULAR);
        }

        val updatedLowerReserve = storage.lowerSideReserve + lowerAmount;
        val updatedHigherReserve = storage.higherSideReserve + balancedHigherAmount;

        val lpTokensToMint = calcLpTokensAmountAfterFirstDeposit(
            lowerAmount,
            higherAmount,
            updatedLowerReserve,
            updatedHigherReserve,
            storage.totalSupply
        );

        return {
            updatedLowerReserve,
            updatedHigherReserve,
            lpTokensToMint,
        };
    }

    // 'balancedLowerAmount = higherAmount * lower / higher'
    val balancedLowerAmount: coins = mulDivFloor(
        higherAmount,
        storage.lowerSideReserve,
        storage.higherSideReserve
    );

    if (balancedLowerAmount < lowerAdditionalParams.minAmountToDeposit) {
        // TODO: fail lp
        throw LIQUIDITY_PROVISIONING_SLIPPAGE_FAILED
    }

    // refund lower lp excesses if we received more than we can accept
    if (lowerAmount > balancedLowerAmount) {
        val liquidityExcessesRefundMsg = createMessage({
            body: PayoutFromPool {
                otherVault: storage.higherVault,
                amount: lowerAmount - balancedLowerAmount,
                receiver: lpTokensReceiver,
                payloadToForward: lowerAdditionalParams.payloadOnSuccess,
            },
            bounce: false,
            dest: storage.lowerVault,
            value: getHalfOfTheMsgValue(inValue),
        });

        liquidityExcessesRefundMsg.send(SEND_MODE_REGULAR);
    }

    val updatedLowerReserve = storage.lowerSideReserve + balancedLowerAmount;
    val updatedHigherReserve = storage.higherSideReserve + higherAmount;

    val lpTokensToMint = calcLpTokensAmountAfterFirstDeposit(
        lowerAmount,
        higherAmount,
        updatedLowerReserve,
        updatedHigherReserve,
        storage.totalSupply
    );

    return {
        updatedLowerReserve,
        updatedHigherReserve,
        lpTokensToMint,
    };
}

type AllowedMessages = NotifyPoolAboutLiquidityDeposit | SwapIn

fun onInternalMessage(in: InMessage) {
    val msg = lazy AllowedMessages.fromSlice(in.body);

    match (msg) {
        NotifyPoolAboutLiquidityDeposit => {
            var storage = lazy AmmPoolStorage.load();

            assert (
                in.senderAddress.isAddressOfLiquidityDeposit(
                    storage.lowerVault,
                    storage.higherVault,
                    msg.lowerAmount,
                    msg.higherAmount,
                    msg.extra,
                    storage.liquidityDepositCode
                )
            ) throw BAD_LIQUIDITY_DEPOSIT_NOTIFY_MSG_SENDER;

            assert (msg.lowerAmount > 0 && msg.higherAmount > 0) throw BAD_LIQUIDITY_AMOUNT;

            val lowerAdditionalParams = lazy msg.lowerAdditionalParams.load();
            val higherAdditionalParams = lazy msg.higherAdditionalParams.load();

            val extra = lazy msg.extra.load();

            assert (
                blockchain.now() >
                max(lowerAdditionalParams.lpTimeout, higherAdditionalParams.lpTimeout)
            ) throw LIQUIDITY_PROVISIONING_TIMEOUT_EXCEEDED;

            val liqProvisioningResult = handleReservesUpdate(
                msg.lowerAmount,
                msg.higherAmount,
                lowerAdditionalParams,
                higherAdditionalParams,
                extra.lpTokensReceiver,
                in.valueCoins
            );

            // update reserves
            storage.lowerSideReserve = liqProvisioningResult.updatedLowerReserve;
            storage.higherSideReserve = liqProvisioningResult.updatedHigherReserve;

            // update balance
            storage.totalSupply += liqProvisioningResult.lpTokensToMint;

            // Mint LP tokens, amm pool acts as the jetton minter for lp jettons
            storage.save();
        }
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
                            storage.ammPoolCode,
                            storage.liquidityDepositCode
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
