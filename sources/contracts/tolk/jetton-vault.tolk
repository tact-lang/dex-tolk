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

fun createSliceWithOneZeroBit(): slice
    asm "b{0} PUSHSLICE"

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
                    val refundMsg = createMessage({
                        body: AskToTransfer {
                            queryId: msg.queryId,
                            jettonAmount: msg.jettonAmount,
                            transferRecipient: msg.transferInitiator,
                            sendExcessesTo: msg.transferInitiator,
                            customPayload: null,
                            forwardTonAmount: 1,
                            forwardPayload: createSliceWithOneZeroBit(),
                        },
                        bounce: false,
                        dest: in.senderAddress,
                        value: 0,
                    });
                    refundMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE |
                    SEND_MODE_IGNORE_ERRORS);

                    commitContractDataAndActions();
                    throw error
                }

                // if we passed the proof check, we can save new address
                storage.jettonWallet = in.senderAddress;
                storage.save();
                commitContractDataAndActions();
            }

            if (in.senderAddress != storage.jettonWallet!) {
                //  TODO: return funds
                commitContractDataAndActions();
                throw 100
            }

            val result = handleAction(
                msg.jettonVaultPayload.action,
                msg.jettonAmount,
                msg.transferInitiator,
                in.valueCoins,
                in.senderAddress
            );

            if (!result) {
                //  TODO: return funds
                commitContractDataAndActions();
                throw 100
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

            var destination: address | AutoDeployAddress;

            match (action.destination) {
                LiquidityDepositWithInitData => {
                    val storage = lazy JettonVaultStorage.load();
                    val sortedAddressesAndAmounts = sortAddressesAndAmounts(
                        contract.getAddress(),
                        action.destination.otherVault,
                        jettonAmount,
                        action.destination.otherAmount
                    );

                    val lpTokensReceiver = action.lpTokensReceiver != null
                         ? action.lpTokensReceiver
                         : transferInitiator;

                    destination = calcLiquidityDepositStateInit(
                        sortedAddressesAndAmounts.lower,
                        sortedAddressesAndAmounts.higher,
                        sortedAddressesAndAmounts.lowerAmount,
                        sortedAddressesAndAmounts.higherAmount,
                        (lpTokensReceiver, action.destination.contractId),
                        storage.liquidityDepositContractCode
                    );
                }
                LiquidityDepositAddress => {
                    destination = action.destination;
                }
            }

            val storage = lazy JettonVaultStorage.load();

            val liquidityDepositNotifyMsg = createMessage({
                body: PartHasBeenDeposited {
                    amount: jettonAmount,
                    additionalParams: action.additionalParams,
                    ammPoolCode: storage.ammPoolCode,
                    liquidityDepositCode: storage.liquidityDepositContractCode,
                    jettonWalletCode: storage.jettonWalletCode,
                },
                bounce: false,
                dest: destination,
                value: 0,
            });
            liquidityDepositNotifyMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);

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
