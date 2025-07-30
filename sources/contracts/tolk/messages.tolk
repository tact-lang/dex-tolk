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

struct LpDepositPart {
    destination: LiquidityDepositDestination
    additionalParams: LpAdditionalParams
    lpTokensReceiver: address?
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
}

struct (0x642b7d07) NotifyPoolAboutLiquidityDeposit {
    lowerAmount: coins
    higherAmount: coins
    extra: Cell<LiquidityDepositExtraFields>
    higherAdditionalParams: Cell<LpAdditionalParams>?
    lowerAdditionalParams: Cell<LpAdditionalParams>?
}

struct (0x2d8b123a) PayoutFromTonVault {
    body: cell?
}
