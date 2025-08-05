import "errors"
import "math"
import "messages"
import "storage"

fun LiquidityDepositStorage.load() {
    return LiquidityDepositStorage.fromCell(contract.getData());
}

fun LiquidityDepositStorage.save(self) {
    contract.setData(self.toCell());
}

type AllowedMessages = PartHasBeenDeposited

fun onInternalMessage(in: InMessage) {
    val msg = lazy AllowedMessages.fromSlice(in.body);

    match (msg) {
        PartHasBeenDeposited => {
            var storage = lazy LiquidityDepositStorage.load();

            if (in.senderAddress == storage.lowerVault) {
                assert (msg.amount == storage.lowerAmount) throw INCORRECT_LIQUIDITY_DEPOSIT_AMOUNT;
                storage.lowerAdditionalParams = msg.additionalParams;
                storage.isLowerSideFilled = true;
            } else if (in.senderAddress == storage.higherVault) {
                assert (
                    msg.amount == storage.higherAmount
                ) throw INCORRECT_LIQUIDITY_DEPOSIT_AMOUNT;
                storage.higherAdditionalParams = msg.additionalParams;
                storage.isHigherSideFilled = true;
            } else {
                throw MSG_NOT_FROM_VAULTS;
            }

            assert (storage.lowerVault != storage.higherVault) throw VAULTS_MUST_BE_DIFFFERENT;
            // if both sides are filled, we can send deposit msg
            if (storage.isLowerSideFilled && storage.isHigherSideFilled) {
                // check that sort is correct, could be security issue
                val sortedAddresses = sortAddresses(storage.lowerVault, storage.higherVault);
                assert (sortedAddresses.lower == storage.lowerVault) throw VAULTS_MUST_BE_SORTED;

                val notifyPoolAboutLpMsg = createMessage({
                    body: NotifyPoolAboutLiquidityDeposit {
                        lowerAmount: storage.lowerAmount,
                        higherAmount: storage.higherAmount,
                        extra: storage.extra,
                        lowerAdditionalParams: storage.lowerAdditionalParams!,
                        higherAdditionalParams: storage.higherAdditionalParams!,
                    },
                    // TODO: add option to skip deploy and just message to address here
                    dest: calcAmmPoolStateInit(
                        storage.lowerVault,
                        storage.higherVault,
                        msg.ammPoolCode,
                        msg.liquidityDepositCode,
                        msg.jettonWalletCode
                    ),
                    bounce: false,
                    value: 0,
                });

                notifyPoolAboutLpMsg.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_DESTROY);
            }

            storage.save();
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

get fun storage(): LiquidityDepositStorage {
    return LiquidityDepositStorage.load();
}

struct LiquidityDepositStatus {
    isLowerSideFilled: bool
    isHigherSideFilled: bool
}

get fun status(): LiquidityDepositStatus {
    val storage = lazy LiquidityDepositStorage.load();

    return {
        isLowerSideFilled: storage.isLowerSideFilled,
        isHigherSideFilled: storage.isHigherSideFilled,
    };
}
