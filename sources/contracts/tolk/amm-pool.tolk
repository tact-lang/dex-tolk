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

            if (storage.lowerSideReserve == 0 || storage.higherSideReserve == 0) {
                // TODO: return funds
                throw NO_LIQUIDITY_IN_POOL
            }

            val swap = lazy msg.swap.load();

            // TODO: maybe we can handle timeout check inside handleSwap too
            if (swap.parameters.timeout > 0 && swap.parameters.timeout < blockchain.now()) {
                // TODO: return funds
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
