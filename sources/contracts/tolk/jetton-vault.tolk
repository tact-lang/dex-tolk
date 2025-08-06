import "errors"
import "math"
import "messages"
import "proof"
import "storage"
import "lp-jettons/lp-jettons-messages.tolk"

struct JettonVaultStorage {
    jettonMaster: address
    jettonWallet: address?
    // code cells
    ammPoolCode: cell
    liquidityDepositContractCode: cell
    jettonWalletCode: cell
}

fun JettonVaultStorage.load() {
    return JettonVaultStorage.fromCell(contract.getData());
}

fun JettonVaultStorage.save(self) {
    contract.setData(self.toCell());
}

@pure
@inline
fun address.isOnBasechain(self) {
    // if address is non-internal, this will throw
    // but its okay, user-side malicious input
    return self.getWorkchain() == BASECHAIN;
}

type AllowedMessagesForJettonVault = JettonTransferNotificationWithVaultAction | PayoutFromPool

fun onInternalMessage(in: InMessage) {
    var storage = JettonVaultStorage.load();

    val msg = lazy AllowedMessagesForJettonVault.fromSlice(in.body);

    match (msg) {
        JettonTransferNotificationWithVaultAction => {
            if (storage.jettonWallet == null) {
                // TODO: handle proofs
                try {
                    checkProof(msg.jettonVaultPayload.proof, storage.jettonMaster, in.senderAddress);
                } catch (error) {
                    // refund if error
                    msg.refundWithError(in.senderAddress, error);
                }

                // if we passed the proof check, we can save new address
                storage.jettonWallet = in.senderAddress;
                storage.save();
                commitContractDataAndActions();
            }

            if (in.senderAddress != storage.jettonWallet!) {
                msg.refundWithError(in.senderAddress, SENDER_IS_NOT_THE_VAULT_JETTON_WALLET);
            }

            val isEnoughGasForaction = handleAction(
                msg.jettonVaultPayload.action,
                msg.jettonAmount,
                msg.transferInitiator,
                in.valueCoins,
                in.senderAddress
            );

            if (!isEnoughGasForaction) {
                msg.refundWithError(in.senderAddress, GAS_LOW_FOR_ACTION);
            }
        }
        PayoutFromPool => {
            val storage = lazy JettonVaultStorage.load();

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

            // TODO: handle jetton fee
            var remaininValue = in.valueCoins - 1;
            remaininValue = min(remaininValue, 0);

            val payoutFromPoolMsg = createMessage({
                body: AskToTransfer {
                    queryId: 0,
                    jettonAmount: msg.amount,
                    sendExcessesTo: msg.receiver,
                    forwardTonAmount: remaininValue,
                    transferRecipient: msg.receiver,
                    // ugly, TVM12 builder->slice waiting room
                    forwardPayload: beginCell().storeMaybeRef(msg.payloadToForward).endCell()
                        .beginParse(),
                    customPayload: null,
                },
                bounce: false,
                dest: storage.jettonWallet!,
                value: 0,
            });

            payoutFromPoolMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
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

struct JettonVaultInfo {
    jettonMaster: address
    jettonWallet: address?
}

// get methods
get fun storage(): JettonVaultInfo {
    val storage = lazy JettonVaultStorage.load();

    return { jettonMaster: storage.jettonMaster, jettonWallet: storage.jettonWallet };
}

// TODO: inline_ref?
fun handleAction(
    actionCell: Cell<JettonVaultAction>,
    jettonAmount: coins,
    transferInitiator: address,
    inValue: coins,
    sender: address,
) {
    val action = lazy actionCell.load();

    match (action) {
        LpDepositPartAction => {
            // TODO: fees
            val protocolGasFee = 1;

            if (inValue < protocolGasFee) {
                return false;
            }

            val storage = lazy JettonVaultStorage.load();

            match (action.destination) {
                LiquidityDepositWithInitData => {
                    val sortedAddressesAndAmounts = sortAddressesAndAmounts(
                        contract.getAddress(),
                        action.destination.otherVault,
                        jettonAmount,
                        action.destination.otherAmount
                    );

                    val lpTokensReceiver = action.lpTokensReceiver != null
                         ? action.lpTokensReceiver
                         : transferInitiator;

                    val destinationNotify = calcLiquidityDepositStateInit(
                        sortedAddressesAndAmounts.lower,
                        sortedAddressesAndAmounts.higher,
                        sortedAddressesAndAmounts.lowerAmount,
                        sortedAddressesAndAmounts.higherAmount,
                        (lpTokensReceiver, action.destination.contractId),
                        storage.liquidityDepositContractCode
                    );

                    val liquidityDepositNotifyMsg = createMessage({
                        body: PartHasBeenDeposited {
                            amount: jettonAmount,
                            additionalParams: action.additionalParams,
                            ammPoolCode: storage.ammPoolCode,
                            liquidityDepositCode: storage.liquidityDepositContractCode,
                            jettonWalletCode: storage.jettonWalletCode,
                        },
                        bounce: false,
                        dest: destinationNotify,
                        value: 0,
                    });
                    liquidityDepositNotifyMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
                }
                LiquidityDepositAddress => {
                    // TODO: func with dest as param
                    val liquidityDepositNotifyMsg = createMessage({
                        body: PartHasBeenDeposited {
                            amount: jettonAmount,
                            additionalParams: action.additionalParams,
                            ammPoolCode: storage.ammPoolCode,
                            liquidityDepositCode: storage.liquidityDepositContractCode,
                            jettonWalletCode: storage.jettonWalletCode,
                        },
                        bounce: false,
                        dest: action.destination,
                        value: 0,
                    });
                    liquidityDepositNotifyMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
                }
            }

            return true;
        }
        SwapRequestAction => {
            val request = action.request;

            val receiver = request.receiver != null ? request.receiver : transferInitiator;
            val hops = request.swap.getNumberOfHops();

            // TODO: fees
            val protocolGasFee = hops + 1;
            if (inValue < protocolGasFee) {
                return false;
            }

            // TODO: jetton fee
            val payoutGasFee = 1;

            val isFeeValid = sender.isOnBasechain() && receiver.isOnBasechain() &&
            (inValue > protocolGasFee + payoutGasFee);

            if (!isFeeValid) {
                return false;
            }

            val swapInMsg = createMessage({
                body: SwapIn {
                    amount: jettonAmount,
                    receiver,
                    swap: request.swap.toCell(),
                    multihopInfo: null,
                },
                bounce: false,
                dest: request.pool,
                value: 0,
            });
            swapInMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);

            return true;
        }
        else => {
            return false;
        }
    }
}
