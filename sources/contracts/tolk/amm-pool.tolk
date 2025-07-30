import "@stdlib/gas-payments"
import "errors"
import "math"
import "messages"
import "storage"

fun AmmPoolStorage.load() {
    return AmmPoolStorage.fromCell(contract.getData());
}

fun AmmPoolStorage.save(self) {
    contract.setData(self.toCell());
}

@pure
fun AmmPoolStorage.isAddressOneOfTheVaults(self, addr: address) {
    return self.lowerVault == addr || self.higherVault == addr;
}

// fun AmmPoolStorage.get
//
// math
// 0.3%, same as uniswap v2
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

type AllowedMessages = NotifyPoolAboutLiquidityDeposit | SwapIn

fun onInternalMessage(in: InMessage) {
    val msg = lazy AllowedMessages.fromSlice(in.body);

    match (msg) {
        NotifyPoolAboutLiquidityDeposit => {}
        SwapIn => {
            var storage = lazy AmmPoolStorage.load();

            // let's assume msg comes from lowerVault
            // and later change default values if its not
            var inVault = storage.lowerVault;
            var outVault = storage.higherVault;

            var inReserve = storage.lowerSideReserve;
            var outReserve = storage.higherSideReserve;
            var isSwapFromHigherVault = false;

            var incomingVault = createAddressNone();
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

            // if we got the message from the left
            // we dont need to change anything
            if (incomingVault == storage.higherVault) {
                inVault = storage.higherVault;
                outVault = storage.lowerVault;
                inReserve = storage.higherSideReserve;
                outReserve = storage.lowerSideReserve;
                isSwapFromHigherVault = true;
            }

            if (inReserve == 0 || outReserve == 0) {
                // TODO: return funds
                throw NO_LIQUIDITY_IN_POOL
            }

            val swap = lazy msg.swap.load();

            if (swap.parameters.timeout > 0 && swap.parameters.timeout < blockchain.now()) {
                // TODO: return funds
                throw SWAP_TIMEOUT_EXCEEDED
            }

            var updatedInReserve: coins;
            var updatedOutReserve: coins;

            // todo: swap.tolk + handle swap there + load params from storage
            // based on incomingVault
            match (swap.swapInfo) {
                ExactInSwap => {
                    // 1. calculate amountIn with deducted pool fee
                    val amountInWithAppliedPoolFee = calcAmountInWithPoolFeeApplied(msg.amount);

                    // 2. calculate inReserve with deducted pool fee
                    val updatedInReserveWithAppliedFee = inReserve + amountInWithAppliedPoolFee;

                    // 3. update reserves after swap, calculating updatedOutReserve
                    //    to keep constant product formula invariant 'x*y = k' valid
                    updatedInReserve = inReserve + msg.amount;
                    updatedOutReserve = mulDivFloor(
                        outReserve,
                        inReserve,
                        updatedInReserveWithAppliedFee
                    );

                    // 4. calculate amountOut as diff between reserves
                    val amountOut = outReserve - updatedOutReserve;

                    if (amountOut < swap.swapInfo.minAmountOut) {
                        // TODO: return funds
                        throw AMOUNT_OUT_IS_LESS_THAN_LIMIT
                    }

                    match (swap.swapInfo.nextStep) {
                        Cell<SwapStep> => {
                            val nextSwapStep = lazy swap.swapInfo.nextStep.load();

                            val nextStepSwapMsg = createMessage({
                                body: SwapIn {
                                    receiver: msg.receiver,
                                    amount: amountOut,
                                    multihopInfo: MultihopInfo {
                                        outVault,
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
                                    otherVault: inVault,
                                    payloadToForward: swap.parameters.payloadOnSuccess,
                                    receiver: msg.receiver,
                                },
                                bounce: false,
                                dest: outVault,
                                value: 0,
                            });

                            payoutFromVaultMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
                        }
                    }
                }
                ExactOutSwap => {
                    // 1. calculate updatedOutReserve by deducting exactOutAmount
                    updatedOutReserve = outReserve - swap.swapInfo.exactOutAmount;

                    if (updatedOutReserve <= 0) {
                        // TODO: return funds
                        throw INSUFFICIENT_RESERVES_FOR_EXACT_OUT_VALUE
                    }

                    // 2. calculate requiredAmountInWithPoolFeeApplied so that we
                    //    keep constant product formula invariant valid
                    val requiredAmountInWithPoolFeeApplied = calcRequiredAmountInWithPoolFeeApplied(
                        updatedOutReserve,
                        inReserve,
                        swap.swapInfo.exactOutAmount
                    );

                    if (requiredAmountInWithPoolFeeApplied > msg.amount) {
                        // TODO: return funds
                        throw INSUFFICIENT_IN_AMOUNT_FOR_EXACT_OUT_VALUE
                    }

                    // 3. if we received more inAmount than we need for swap,
                    //    then refund the excesses
                    if (msg.amount > requiredAmountInWithPoolFeeApplied) {
                        val cashbackAddress = swap.swapInfo.cashbackAddress != null
                             ? swap.swapInfo.cashbackAddress
                             : msg.receiver;

                        val refundExcessesMsg = createMessage({
                            body: PayoutFromPool {
                                otherVault: outVault,
                                amount: msg.amount - requiredAmountInWithPoolFeeApplied,
                                receiver: cashbackAddress,
                                payloadToForward: swap.parameters.payloadOnSuccess,
                            },
                            bounce: false,
                            dest: inVault,
                            value: getHalfOfTheMsgValue(in.valueCoins),
                        });

                        refundExcessesMsg.send(SEND_MODE_REGULAR);
                    }

                    // 4. calculate updatedInReserve with actual inAmount for swap
                    updatedInReserve = inReserve + requiredAmountInWithPoolFeeApplied;

                    val payoutFromVaultMsg = createMessage({
                        body: PayoutFromPool {
                            amount: swap.swapInfo.exactOutAmount,
                            otherVault: inVault,
                            payloadToForward: swap.parameters.payloadOnSuccess,
                            receiver: msg.receiver,
                        },
                        bounce: false,
                        dest: outVault,
                        value: 0,
                    });

                    payoutFromVaultMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
                }
            }

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
