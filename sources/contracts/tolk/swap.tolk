import "@stdlib/gas-payments"
import "errors"
import "messages"
import "storage"

// math
const LiquidityProvidersPoolFee = 3
const PoolFeePrecision = 1000

@inline
@pure
fun calcAmountInWithPoolFeeApplied(amountIn: coins) {
    return mulDivFloor(amountIn, PoolFeePrecision - LiquidityProvidersPoolFee, PoolFeePrecision);
}

@inline
@pure
fun calcRequiredAmountInWithPoolFeeApplied(
    updatedOutReserve: coins,
    inReserve: coins,
    exactOutAmount: coins,
) {
    val numenator = updatedOutReserve * (PoolFeePrecision - LiquidityProvidersPoolFee);
    return mulDivFloor(inReserve, exactOutAmount * PoolFeePrecision, numenator);
}

// utils
@inline
fun getHalfOfTheMsgValue(value: coins) {
    return (value - calculateGasFee(BASECHAIN, getGasConsumedAtTheMoment())) / 2;
}

struct SwapContext {
    inVault: address
    outVault: address
    inReserve: coins
    outReserve: coins
    isSwapFromHigherVault: bool
}

@inline
@pure
fun AmmPoolStorage.getSwapContext(self, incomingVault: address): SwapContext {
    if (incomingVault == self.lowerVault) {
        return {
            inVault: self.lowerVault,
            outVault: self.higherVault,
            inReserve: self.lowerSideReserve,
            outReserve: self.higherSideReserve,
            isSwapFromHigherVault: false,
        };
    } else {
        return {
            inVault: self.higherVault,
            outVault: self.lowerVault,
            inReserve: self.higherSideReserve,
            outReserve: self.lowerSideReserve,
            isSwapFromHigherVault: true,
        };
    }
}

fun handleSwap(
    swap: Swap,
    inAmount: coins,
    receiver: address,
    inValue: coins,
    incomingVault: address,
) {
    val storage = lazy AmmPoolStorage.load();
    val ctx = storage.getSwapContext(incomingVault);

    var updatedInReserve: coins;
    var updatedOutReserve: coins;

    match (swap.swapInfo) {
        ExactInSwap => {
            // 1. calculate amountIn with deducted pool fee
            val amountInWithAppliedPoolFee = calcAmountInWithPoolFeeApplied(inAmount);

            // 2. calculate inReserve with deducted pool fee
            val updatedInReserveWithAppliedFee = ctx.inReserve + amountInWithAppliedPoolFee;

            // 3. update reserves after swap, calculating updatedOutReserve
            //    to keep constant product formula invariant 'x*y = k' valid
            updatedInReserve = ctx.inReserve + inAmount;
            updatedOutReserve = mulDivFloor(
                ctx.outReserve,
                ctx.inReserve,
                updatedInReserveWithAppliedFee
            );

            // 4. calculate amountOut as diff between reserves
            val amountOut = ctx.outReserve - updatedOutReserve;

            if (amountOut < swap.swapInfo.minAmountOut) {
                // TODO: return funds
                throw AMOUNT_OUT_IS_LESS_THAN_LIMIT
            }

            match (swap.swapInfo.nextStep) {
                Cell<SwapStep> => {
                    val nextSwapStep = lazy swap.swapInfo.nextStep.load();

                    val nextStepSwapMsg = createMessage({
                        body: SwapIn {
                            receiver,
                            amount: amountOut,
                            multihopInfo: MultihopInfo {
                                outVault: ctx.outVault,
                                lowerVault: storage.lowerVault,
                                higherVault: storage.higherVault,
                            }
                                .toCell(),
                            swap: Swap {
                                parameters: swap.parameters,
                                swapInfo: ExactInSwap {
                                    minAmountOut: nextSwapStep.minAmountOut,
                                    nextStep: nextSwapStep.nextStep,
                                },
                            }
                                .toCell(),
                        },
                        bounce: false,
                        dest: nextSwapStep.pool,
                        value: 0,
                    });

                    nextStepSwapMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
                }
                null => {
                    val payoutFromVaultMsg = createMessage({
                        body: PayoutFromPool {
                            amount: amountOut,
                            otherVault: ctx.inVault,
                            payloadToForward: swap.parameters.payloadOnSuccess,
                            receiver,
                        },
                        bounce: false,
                        dest: ctx.outVault,
                        value: 0,
                    });

                    payoutFromVaultMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
                }
            }
        }
        ExactOutSwap => {
            // 1. calculate updatedOutReserve by deducting exactOutAmount
            updatedOutReserve = ctx.outReserve - swap.swapInfo.exactOutAmount;

            if (updatedOutReserve <= 0) {
                // TODO: return funds
                throw INSUFFICIENT_RESERVES_FOR_EXACT_OUT_VALUE
            }

            // 2. calculate requiredAmountInWithPoolFeeApplied so that we
            //    keep constant product formula invariant valid
            val requiredAmountInWithPoolFeeApplied = calcRequiredAmountInWithPoolFeeApplied(
                updatedOutReserve,
                ctx.inReserve,
                swap.swapInfo.exactOutAmount
            );

            if (requiredAmountInWithPoolFeeApplied > inAmount) {
                // TODO: return funds
                throw INSUFFICIENT_IN_AMOUNT_FOR_EXACT_OUT_VALUE
            }

            // 3. if we received more inAmount than we need for swap,
            //    then refund the excesses
            if (inAmount > requiredAmountInWithPoolFeeApplied) {
                val cashbackAddress = swap.swapInfo.cashbackAddress != null
                     ? swap.swapInfo.cashbackAddress
                     : receiver;

                val refundExcessesMsg = createMessage({
                    body: PayoutFromPool {
                        otherVault: ctx.outVault,
                        amount: inAmount - requiredAmountInWithPoolFeeApplied,
                        receiver: cashbackAddress,
                        payloadToForward: swap.parameters.payloadOnSuccess,
                    },
                    bounce: false,
                    dest: ctx.inVault,
                    value: getHalfOfTheMsgValue(inValue),
                });

                refundExcessesMsg.send(SEND_MODE_REGULAR);
            }

            // 4. calculate updatedInReserve with actual inAmount for swap
            updatedInReserve = ctx.inReserve + requiredAmountInWithPoolFeeApplied;

            val payoutFromVaultMsg = createMessage({
                body: PayoutFromPool {
                    amount: swap.swapInfo.exactOutAmount,
                    otherVault: ctx.inVault,
                    payloadToForward: swap.parameters.payloadOnSuccess,
                    receiver,
                },
                bounce: false,
                dest: ctx.outVault,
                value: 0,
            });

            payoutFromVaultMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }
    }

    return (updatedInReserve, updatedOutReserve, ctx.isSwapFromHigherVault);
}
