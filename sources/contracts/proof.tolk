import "errors"
import "messages"

fun address.isFromStateInitInBasechain(self, stateInit: StateInit) {
    return AutoDeployAddress {
        stateInit: { code: stateInit.code!, data: stateInit.data! },
        workchain: BASECHAIN,
    }.addressMatches(self);
}

fun checkProof(proof: JettonVaultProof, minter: address, msgSender: address) {
    match (proof) {
        NoProof => {
            return;
        }
        MinterDiscoveryProof => {}
        OnchainGetterProof => {
            val vaultJettonWallet = calcJettonWalletAddressWithOnchainGetter(
                contract.getAddress(),
                proof.jettonMinterStateInit.data!,
                proof.jettonMinterStateInit.code!,
                minter
            );

            assert (
                msgSender == vaultJettonWallet &&
                minter.isFromStateInitInBasechain(proof.jettonMinterStateInit)
            ) throw INVALID_STATE_INIT_PROOF;
        }
        StateToTheBlockProof => {}
    }
}

// helper function to calculate jetton wallet address synchronously
// inside tvm with jetton minter state and data, using RUNVM opcode
// fmt-ignore
fun calcJettonWalletAddressWithOnchainGetter(owner: address, jettonData: cell, jettonCode: cell, jettonMaster: address): address 
    asm
    "c7 PUSHCTR"
    "0 INDEX" // Unpack singleton from c7
    // https://docs.ton.org/v3/documentation/tvm/tvm-initialization#control-register-c7
    "SWAP"
    "8 SETINDEX"
    "SWAP"
    "DUP"
    "ROTREV"
    "10 SETINDEX"
    "1 TUPLE" // Make it singleton back
    // owner md mc c7
    "ROTREV"
    "CTOS"         // owner_addr c7 md mc
    "2 PUSHINT"       // owner_addr c7 md mc args"
    "103289 PUSHINT"  // owner_addr c7 md mc args get_jwa_method_id"
    "5 0 REVERSE"     // owner_addr get_jwa_method_id args mc md c7"
    "53 RUNVM"        // address exit_code c4' c5'"
    // TODO check RUNVM exit code
    "3 BLKDROP" // address";
