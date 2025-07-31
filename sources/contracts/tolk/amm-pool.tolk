import "@stdlib/gas-payments"
import "errors"
import "liquidity"
import "math"
import "messages"
import "storage"
import "swap"
import "lp-jettons/lp-errors"
import "lp-jettons/lp-jetton-utils"
import "lp-jettons/lp-jettons-messages.tolk"

@pure
@inline
fun uint32.isTimeoutExceeded(self) {
    return self > 0 && self < blockchain.now();
}

fun onBouncedMessage(in: InMessageBounced) {
    in.bouncedBody.skipBouncedPrefix();
    // process only mint bounces; on other messages, an exception will be thrown, it's okay
    val msg = lazy LpJettonTransferInternal.fromSlice(in.bouncedBody);

    var storage = lazy AmmPoolStorage.load();
    storage.totalSupply -= msg.jettonAmount;
    storage.save();
}

type AllowedMessages =
    | NotifyPoolAboutLiquidityDeposit
    | SwapIn
    | LiquidityWithdrawViaBurnNotification

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

            val maxLpTimeout: uint32 = max(
                lowerAdditionalParams.lpTimeout,
                higherAdditionalParams.lpTimeout
            );
            assert (maxLpTimeout.isTimeoutExceeded()) throw LIQUIDITY_PROVISIONING_TIMEOUT_EXCEEDED;

            val reserveUpdates = handleReservesUpdate(
                msg.lowerAmount,
                msg.higherAmount,
                lowerAdditionalParams,
                higherAdditionalParams,
                extra.lpTokensReceiver,
                in.valueCoins
            );

            // update reserves
            storage.lowerSideReserve = reserveUpdates.updatedLowerReserve;
            storage.higherSideReserve = reserveUpdates.updatedHigherReserve;

            // update total lp amount
            storage.totalSupply += reserveUpdates.lpTokensToMint;
            storage.save();

            // Mint LP tokens, amm pool acts as the jetton minter for lp jettons
            val successForwarsPayload = createSuccessfulForwardPayload(
                lowerAdditionalParams.payloadOnSuccess,
                higherAdditionalParams.payloadOnSuccess
            );

            val lpJettonMintMsg = createMessage({
                body: LpJettonTransferInternal {
                    queryId: 0,
                    jettonAmount: reserveUpdates.lpTokensToMint,
                    transferInitiator: contract.getAddress(),
                    sendExcessesTo: extra.lpTokensReceiver,
                    sendAllTonsInNotifyFlag: true,
                    forwardTonAmount: 0,
                    forwardPayload: successForwarsPayload,
                },
                // actually this is the only message in whole T-Dex
                // that is send as bounceable, since we handle it
                bounce: true,
                dest: calcLpJettonWalletStateInit(
                    extra.lpTokensReceiver,
                    contract.getAddress(),
                    storage.jettonWalletCode
                ),
                value: 0,
            });

            lpJettonMintMsg.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }
        SwapIn => {
            var storage = lazy AmmPoolStorage.load();

            val incomingVault = getIncomingVault(msg.multihopInfo, in.senderAddress);

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

            if (swap.parameters.timeout.isTimeoutExceeded()) {
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
        LiquidityWithdrawViaBurnNotification => {
            var storage = lazy AmmPoolStorage.load();

            assert (
                in.senderAddress.isAddressOfLpJettonWallet(
                    msg.burnInitiator,
                    contract.getAddress(),
                    storage.jettonWalletCode
                )
            ) throw ERROR_NOT_VALID_WALLET;

            val withdrawalParameters = msg.parameters.load();
            assert (
                withdrawalParameters.timeout.isTimeoutExceeded()
            ) throw LIQUIDITY_WITHDRAWAL_TIMEOUT_EXCEEDED;

            val (lowerAmountOut, higherAmountOut) = calcWithdrawalAmounts(
                msg.jettonAmount,
                withdrawalParameters
            );

            storage.totalSupply -= msg.jettonAmount;
            storage.lowerSideReserve -= lowerAmountOut;
            storage.higherSideReserve -= higherAmountOut;

            storage.save();

            // Preserve original balance (more, if we have storage debt)
            reserveToncoinsOnBalance(
                getGasConsumedAtTheMoment(),
                RESERVE_MODE_INCREASE_BY_ORIGINAL_BALANCE | RESERVE_MODE_EXACT_AMOUNT
            );

            val payoutFromLowerVaultMsg = createMessage({
                body: PayoutFromPool {
                    amount: lowerAmountOut,
                    otherVault: storage.higherVault,
                    payloadToForward: withdrawalParameters.liquidityWithdrawPayload,
                    receiver: withdrawalParameters.receiver,
                },
                bounce: false,
                dest: storage.lowerVault,
                value: getHalfOfTheMsgValue(in.valueCoins),
            });
            payoutFromLowerVaultMsg.send(SEND_MODE_BOUNCE_ON_ACTION_FAIL | SEND_MODE_REGULAR);

            val payoutFromHigherVaultMsg = createMessage({
                body: PayoutFromPool {
                    amount: higherAmountOut,
                    otherVault: storage.lowerVault,
                    payloadToForward: withdrawalParameters.liquidityWithdrawPayload,
                    receiver: withdrawalParameters.receiver,
                },
                bounce: false,
                dest: storage.higherVault,
                value: 0,
            });
            payoutFromHigherVaultMsg.send(SEND_MODE_BOUNCE_ON_ACTION_FAIL |
            SEND_MODE_CARRY_ALL_BALANCE);
        }
    }
}

// get methdos
type VaultsWithReserves = SortedAddressesAndAmounts

// pool get methods
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

// minter get methods
struct JettonDataReply {
    totalSupply: int
    mintable: bool
    adminAddress: address
    jettonContent: cell
    jettonWalletCode: cell
}

get fun get_jetton_data(): JettonDataReply {
    val storage = lazy AmmPoolStorage.load();

    return {
        totalSupply: storage.totalSupply,
        mintable: true,
        adminAddress: createAddressNone(),
        jettonContent: createEmptyCell(),
        jettonWalletCode: storage.jettonWalletCode,
    };
}

get fun get_wallet_address(ownerAddress: address): address {
    val storage = lazy AmmPoolStorage.load();

    val addrBuilt = buildAddressOfLpJettonWallet(
        ownerAddress,
        contract.getAddress(),
        storage.jettonWalletCode
    );
    return address.fromValidBuilder(addrBuilt);
}
