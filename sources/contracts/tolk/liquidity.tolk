import "errors"
import "math"
import "messages"
import "storage"
import "swap"
import "lp-jettons/lp-jettons-messages"

struct LiquidityProvisioningResult {
    updatedLowerReserve: coins
    updatedHigherReserve: coins
    lpTokensToMint: coins
}

// @pure
@inline
fun calcLpTokensAmountAfterFirstDeposit(
    lowerAmount: coins,
    higherAmount: coins,
    lowerSideReserve: coins,
    higherSideReserve: coins,
    totalSupply: coins,
) {
    /*
        lpTokens: min(
            (amountADesired * mintedLpTokenTotalSupply) / tokenAReserveBefore,
            (amountB * mintedLpTokenTotalSupply) / tokenBReserveBefore,
        ),
    */
    return min(
        mulDivFloor(lowerAmount, totalSupply, lowerSideReserve - lowerAmount),
        mulDivFloor(higherAmount, totalSupply, higherSideReserve - higherAmount)
    );
}

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
            throw LIQUIDITY_PROVISIONING_SLIPPAGE_FAILED;
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
            balancedHigherAmount,
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
        throw LIQUIDITY_PROVISIONING_SLIPPAGE_FAILED;
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
        balancedLowerAmount,
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

@inline
fun calcWithdrawalAmounts(burnedLpJTokensAmount: coins, parameters: LiquidityWithdrawParameters): (
    coins, coins
) {
    val storage = lazy AmmPoolStorage.load();

    val lowerAmountOut = mulDivFloor(
        burnedLpJTokensAmount,
        storage.lowerSideReserve,
        storage.totalSupply
    );
    assert (
        lowerAmountOut >= parameters.lowerAmountMin
    ) throw WITHDRAWN_LIQUIDITY_AMOUNT_IS_LESS_THAN_LIMIT;

    val higherAmountOut = mulDivFloor(
        burnedLpJTokensAmount,
        storage.higherSideReserve,
        storage.totalSupply
    );

    assert (
        higherAmountOut >= parameters.higherAmountMin
    ) throw WITHDRAWN_LIQUIDITY_AMOUNT_IS_LESS_THAN_LIMIT;

    return (lowerAmountOut, higherAmountOut);
}
