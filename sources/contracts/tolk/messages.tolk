struct (0x74f7a60) PayoutFromPool {
    otherVault: address
    amount: coins
    receiver: address
    payloadToForward: cell?
}

struct SwapStep {
    pool: address
    minAmountOut: coins
    nextStep: Cell<SwapStep>?
}

struct ExactOutSwap {
    cashbackAddress: address?
    exactOutAmount: coins
}

struct ExactInSwap {
    minAmountOut: coins
    nextStep: Cell<SwapStep>?
}

struct SwapParameters {
    timeout: uint32
    payloadOnSuccess: cell?
    payloadOnFailure: cell?
}

type SwapInfo = ExactOutSwap | ExactInSwap

struct Swap {
    swapInfo: SwapInfo
    parameters: SwapParameters
}

fun Swap.getNumberOfHops(self): int {
    match (self.swapInfo) {
        ExactOutSwap => {
            return 1;
        }
        ExactInSwap => {
            return self.swapInfo.nextStep.depth() + 1;
        }
    }
}

struct SwapRequest {
    pool: address
    receiver: address?
    swap: Swap
}

struct MultihopInfo {
    lowerVault: address
    higherVault: address
    outVault: address
}

struct (0xac2f5a38) SwapIn {
    amount: coins
    receiver: address
    swap: Cell<Swap>
    multihopInfo: Cell<MultihopInfo>?
}

struct (0x698cba08) SwapRequestTon {
    amount: coins
    action: Cell<SwapRequest>
}

struct LiquidityDepositWithInitData {
    otherVault: address
    otherAmount: coins
    contractId: uint64
}

type LiquidityDepositAddress = address

type LiquidityDepositDestination = LiquidityDepositWithInitData | LiquidityDepositAddress

struct LpAdditionalParams {
    minAmountToDeposit: coins
    lpTimeout: uint32
    payloadOnSuccess: cell?
    payloadOnFailure: cell?
}

// NOTE: we always should move less used fields
// to the extra ref so they won't be loaded with lazy storage;
//
// we move this fields to the separate ref
// since all storage doesnt fit into single cell
struct LiquidityDepositExtraFields {
    lpTokensReceiver: address
    // on-chain salt for simultaneous lp provisionings
    contractId: uint64
}

struct (0x1b434676) AddLiquidityPartTon {
    amountIn: coins
    destination: LiquidityDepositDestination
    additionalParams: Cell<LpAdditionalParams>
    lpTokensReceiver: address?
}

struct (0xe7a3475f) PartHasBeenDeposited {
    amount: coins
    additionalParams: Cell<LpAdditionalParams>
    ammPoolCode: cell
    liquidityDepositCode: cell
    jettonWalletCode: cell
}

// We are using USDT-like mint opcode for liquidity deposit
// So this operation will be nicely displayed in Tonviewer
struct (0x642b7d07) NotifyPoolAboutLiquidityDeposit {
    lowerAmount: coins
    higherAmount: coins
    extra: Cell<LiquidityDepositExtraFields>
    higherAdditionalParams: Cell<LpAdditionalParams>
    lowerAdditionalParams: Cell<LpAdditionalParams>
}

struct (0x2d8b123a) PayoutFromTonVault {
    body: cell?
}

// jetton vault messages
struct (0xbfa68001) SwapRequestAction {
    request: SwapRequest
}

struct (0x64c08bfc) LpDepositPartAction {
    destination: LiquidityDepositDestination
    additionalParams: Cell<LpAdditionalParams>
    lpTokensReceiver: address?
}

type JettonVaultAction = SwapRequestAction | LpDepositPartAction

struct (0x0) NoProof {}

struct (0x1) MinterDiscoveryProof {}

struct (0x2) OnchainGetterProof {
    jettonMinterStateInit: StateInit
}

struct (0x3) StateToTheBlockProof {
    // TODO: handle all this proof mess later
    stateProof: cell
}

type JettonVaultProof = NoProof | MinterDiscoveryProof | OnchainGetterProof | StateToTheBlockProof

struct (0b0) JettonVaultNotificationPaylaod {
    action: Cell<JettonVaultAction>
    proof: JettonVaultProof
}

// struct (0b0) JettonVaultPayloadInline {
//     data: JettonVaultNotificationPaylaod
// }
// struct (0b1) JettonVaultPayloadRef {
//     ref: cell
//     rest: RemainingBitsAndRefs // should be empty
// }
// type ForwardPayloadValidation = ForwardPayloadInline | ForwardPayloadRef
// 
// TEP-74 JettonNotify, but with forwardPayload serialized as expected fields
struct (0x7362d09c) JettonTransferNotificationWithVaultAction {
    queryId: uint64
    jettonAmount: coins
    transferInitiator: address
    // we want payload to be stored inline
    jettonVaultPayload: JettonVaultNotificationPaylaod
}
