import "errors"
import "math"
import "messages"
import "storage"

struct TonVaultStorage {
    ammPoolCode: cell
    liquidityDepositContractCode: cell
    jettonWalletCode: cell
}

// actually we don't even need Storage.save for this contract
fun TonVaultStorage.load() {
    return TonVaultStorage.fromCell(contract.getData());
}

type AllowedMessages = PayoutFromPool | SwapRequestTon | AddLiquidityPartTon

fun onInternalMessage(in: InMessage) {
    val msg = lazy AllowedMessages.fromSlice(in.body);

    match (msg) {
        PayoutFromPool => {
            val storage = lazy TonVaultStorage.load();
            // TODO: sort in overrided .toCell?
            val sortedAddresses = sortAddresses(contract.getAddress(), msg.otherVault);

            assert (
                in.senderAddress.isAddressOfAmmPool(
                    sortedAddresses.lower,
                    sortedAddresses.higher,
                    storage.ammPoolCode,
                    storage.liquidityDepositContractCode,
                    storage.jettonWalletCode
                )
            ) throw SENDER_SHOULD_BE_AMM_POOL;

            val payoutFromTonVaultMsg = createMessage({
                body: PayoutFromTonVault { body: msg.payloadToForward },
                bounce: false,
                dest: msg.receiver,
                value: msg.amount,
            });

            payoutFromTonVaultMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }
        SwapRequestTon => {
            val amountForFees = in.valueCoins - msg.amount;
            val action = msg.action.load();
            // TODO: think of extension function
            val receiver = action.receiver != null ? action.receiver : in.senderAddress;

            val hops = action.swap.getNumberOfHops();
            val fwdFee = in.originalForwardFee;

            val protocolGasFee = 1;
            val jettonGasFee = 1;
            // TODO: gas check
            assert (amountForFees > protocolGasFee + jettonGasFee) throw NOT_ENOUGH_VALUE_FOR_FEES;

            reserveToncoinsOnBalance(
                msg.amount,
                RESERVE_MODE_EXACT_AMOUNT | RESERVE_MODE_INCREASE_BY_ORIGINAL_BALANCE |
                RESERVE_MODE_BOUNCE_ON_ACTION_FAIL
            );

            val swapInMsg = createMessage({
                body: SwapIn {
                    receiver,
                    amount: msg.amount,
                    swap: action.swap.toCell(),
                    multihopInfo: null,
                },
                bounce: false,
                dest: action.pool,
                value: 0,
            });

            swapInMsg.send(SEND_MODE_BOUNCE_ON_ACTION_FAIL | SEND_MODE_CARRY_ALL_BALANCE);
        }
        AddLiquidityPartTon => {
            // TODO: fees (andrey)
            val protocolGasFee = 1;
            assert (in.valueCoins - msg.amountIn > protocolGasFee) throw NOT_ENOUGH_VALUE_FOR_FEES;

            reserveToncoinsOnBalance(
                msg.amountIn,
                RESERVE_MODE_EXACT_AMOUNT | RESERVE_MODE_INCREASE_BY_ORIGINAL_BALANCE |
                RESERVE_MODE_BOUNCE_ON_ACTION_FAIL
            );

            match (msg.destination) {
                LiquidityDepositWithInitData => {
                    val storage = lazy TonVaultStorage.load();
                    val sortedAddressesAndAmounts = sortAddressesAndAmounts(
                        contract.getAddress(),
                        msg.destination.otherVault,
                        msg.amountIn,
                        msg.destination.otherAmount
                    );

                    val lpTokensReceiver = msg.lpTokensReceiver != null
                         ? msg.lpTokensReceiver
                         : in.senderAddress;

                    val destinationWithInit = calcLiquidityDepositStateInit(
                        sortedAddressesAndAmounts.lower,
                        sortedAddressesAndAmounts.higher,
                        sortedAddressesAndAmounts.lowerAmount,
                        sortedAddressesAndAmounts.higherAmount,
                        (lpTokensReceiver, msg.destination.contractId),
                        storage.liquidityDepositContractCode
                    );

                    val liquidityDepositNotifyMsg = createMessage({
                        body: PartHasBeenDeposited {
                            amount: msg.amountIn,
                            additionalParams: msg.additionalParams,
                            liquidityDepositCode: storage.liquidityDepositContractCode,
                            ammPoolCode: storage.ammPoolCode,
                            jettonWalletCode: storage.jettonWalletCode,
                        },
                        bounce: false,
                        dest: destinationWithInit,
                        value: 0,
                    });

                    liquidityDepositNotifyMsg.send(SEND_MODE_CARRY_ALL_BALANCE |
                    SEND_MODE_BOUNCE_ON_ACTION_FAIL);
                }
                LiquidityDepositAddress => {
                    val storage = lazy TonVaultStorage.load();

                    val liquidityDepositNotifyMsg = createMessage({
                        body: PartHasBeenDeposited {
                            amount: msg.amountIn,
                            additionalParams: msg.additionalParams,
                            liquidityDepositCode: storage.liquidityDepositContractCode,
                            ammPoolCode: storage.ammPoolCode,
                            jettonWalletCode: storage.jettonWalletCode,
                        },
                        bounce: false,
                        dest: msg.destination,
                        value: 0,
                    });

                    liquidityDepositNotifyMsg.send(SEND_MODE_CARRY_ALL_BALANCE |
                    SEND_MODE_BOUNCE_ON_ACTION_FAIL);
                }
            }
            ;
        }
        else => {
            val refundMsg = createMessage({
                bounce: false,
                dest: in.senderAddress,
                value: 0,
            });

            refundMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }
    }
}
