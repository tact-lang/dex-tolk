//  SPDX-License-Identifier: MIT
//  Copyright © 2025 TON Studio

import {Blockchain} from "@ton/sandbox"
import {createJettonAmmPool} from "../utils/environment-tolk"
import {beginCell, toNano} from "@ton/core"
// TODO: change this imports
import {loadPayoutFromPool, loadSendViaJettonTransfer} from "../output/DEX_AmmPool"
// eslint-disable-next-line
import {SendDumpToDevWallet} from "@tondevwallet/traces"
import {JettonVault} from "../output/DEX_JettonVault"
import {findTransactionRequired, flattenTransaction} from "@ton/test-utils"
import {DexOpcodes, DexErrors} from "../tolk-wrappers/DexConstants"

describe("Payloads", () => {
    test("Successful swap should return success payload", async () => {
        const blockchain = await Blockchain.create()

        const {ammPool, vaultA, vaultB, initWithLiquidity, swap} =
            await createJettonAmmPool(blockchain)

        // deploy liquidity deposit contract
        const initialRatio = 10n

        const amountA = toNano(5)
        const amountB = amountA * initialRatio // 1 a == 2 b ratio

        const depositor = vaultA.treasury.walletOwner
        const {getLpWallet} = await initWithLiquidity(depositor, amountA, amountB)
        const depositorLpWallet = await getLpWallet()

        const lpBalanceAfterFirstLiq = await depositorLpWallet.getJettonBalance()
        // check that liquidity deposit was successful
        expect(lpBalanceAfterFirstLiq).toBeGreaterThan(0n)

        const payloadOnSuccess = beginCell().storeStringTail("Success").endCell()

        const amountToSwap = toNano(0.05)
        const expectedOutput = await ammPool.getExpectedOut(vaultA.vault.address, amountToSwap)

        const amountBJettonBeforeSwap = await vaultB.treasury.wallet.getJettonBalance()
        const swapResult = await swap(
            amountToSwap,
            "vaultA",
            expectedOutput,
            0n,
            false,
            null,
            payloadOnSuccess,
        )
        // check that swap was successful
        expect(swapResult.transactions).toHaveTransaction({
            from: vaultA.vault.address,
            to: ammPool.address,
            op: DexOpcodes.SwapIn,
            success: true,
        })

        const payoutTx = findTransactionRequired(swapResult.transactions, {
            from: ammPool.address,
            to: vaultB.vault.address,
            op: DexOpcodes.PayoutFromPool,
            success: true,
        })

        const payoutBody = flattenTransaction(payoutTx).body?.beginParse()
        const parsedPayout = loadPayoutFromPool(payoutBody!!)

        expect(parsedPayout.otherVault).toEqualAddress(vaultA.vault.address)
        expect(parsedPayout.amount).toEqual(expectedOutput)
        expect(parsedPayout.receiver).toEqualAddress(depositor.address)
        expect(parsedPayout.payloadToForward!!).toEqualCell(payloadOnSuccess)

        const tx = findTransactionRequired(swapResult.transactions, {
            from: vaultB.vault.address,
            // TODO: to: vaultB.jettonWallet
            op: JettonVault.opcodes.SendViaJettonTransfer,
            success: true,
        })

        const body = flattenTransaction(tx).body?.beginParse()
        const parsedBody = loadSendViaJettonTransfer(body!!)

        expect(parsedBody.destination).toEqualAddress(depositor.address)
        expect(parsedBody.responseDestination).toEqualAddress(depositor.address)
        expect(parsedBody.forwardPayload.asCell()).toEqualCell(
            beginCell().storeMaybeRef(payloadOnSuccess).endCell(),
        )

        const amountOfJettonBAfterSwap = await vaultB.treasury.wallet.getJettonBalance()
        expect(amountOfJettonBAfterSwap).toBeGreaterThan(amountBJettonBeforeSwap)
    })

    test("Swap failed due to slippage should return failure payload", async () => {
        const blockchain = await Blockchain.create()
        const {ammPool, vaultA, vaultB, initWithLiquidity, swap} =
            await createJettonAmmPool(blockchain)

        // deploy liquidity deposit contract
        const initialRatio = 2n

        const amountA = toNano(1)
        const amountB = amountA * initialRatio // 1 a == 2 b ratio

        const depositor = vaultA.treasury.walletOwner
        const _ = await initWithLiquidity(depositor, amountA, amountB)

        const payloadOnFailure = beginCell().storeStringTail("Failure").endCell()
        const payloadOnSuccess = beginCell().storeStringTail("Success").endCell()

        const amountToSwap = toNano(0.05)
        const expectedOutput =
            (await ammPool.getExpectedOut(vaultA.vault.address, amountToSwap)) + 1n // +1 to fail transaction due to slippage

        const swapResult = await swap(
            amountToSwap,
            "vaultA",
            expectedOutput,
            0n,
            false,
            null,
            payloadOnSuccess,
            payloadOnFailure,
        )

        expect(swapResult.transactions).toHaveTransaction({
            from: vaultA.vault.address,
            to: ammPool.address,
            op: DexOpcodes.SwapIn,
            exitCode: DexErrors.AMOUNT_OUT_IS_LESS_THAN_LIMIT,
        })

        const payoutTx = findTransactionRequired(swapResult.transactions, {
            from: ammPool.address,
            to: vaultA.vault.address,
            op: DexOpcodes.PayoutFromPool,
            success: true,
        })

        const payoutBody = flattenTransaction(payoutTx).body?.beginParse()
        const parsedPayout = loadPayoutFromPool(payoutBody!!)

        expect(parsedPayout.otherVault).toEqualAddress(vaultB.vault.address)
        expect(parsedPayout.amount).toEqual(amountToSwap)
        expect(parsedPayout.receiver).toEqualAddress(depositor.address)
        expect(parsedPayout.payloadToForward!!).toEqualCell(payloadOnFailure)
    })

    test("Swap failed due to timeout should return failure payload", async () => {
        const blockchain = await Blockchain.create()
        const {ammPool, vaultA, vaultB, initWithLiquidity, swap} =
            await createJettonAmmPool(blockchain)

        // deploy liquidity deposit contract
        const initialRatio = 2n

        const amountA = toNano(1)
        const amountB = amountA * initialRatio // 1 a == 2 b ratio

        const depositor = vaultA.treasury.walletOwner

        const _ = await initWithLiquidity(depositor, amountA, amountB)

        const payloadOnFailure = beginCell().storeStringTail("Failure").endCell()
        const payloadOnSuccess = beginCell().storeStringTail("Success").endCell()

        const amountToSwap = toNano(0.05)
        const expectedOutput = await ammPool.getExpectedOut(vaultA.vault.address, amountToSwap)
        const timeout = BigInt(Math.floor(Date.now() / 1000) - 42) // 42 seconds ago, random number

        const swapResult = await swap(
            amountToSwap,
            "vaultA",
            expectedOutput,
            timeout,
            false,
            null,
            payloadOnSuccess,
            payloadOnFailure,
        )

        expect(swapResult.transactions).toHaveTransaction({
            from: vaultA.vault.address,
            to: ammPool.address,
            op: DexOpcodes.SwapIn,
            exitCode: DexErrors.SWAP_TIMEOUT_EXCEEDED,
        })

        const payoutTx = findTransactionRequired(swapResult.transactions, {
            from: ammPool.address,
            to: vaultA.vault.address,
            op: DexOpcodes.PayoutFromPool,
            success: true,
        })

        const payoutBody = flattenTransaction(payoutTx).body?.beginParse()
        const parsedPayout = loadPayoutFromPool(payoutBody!!)

        expect(parsedPayout.otherVault).toEqualAddress(vaultB.vault.address)
        expect(parsedPayout.amount).toEqual(amountToSwap)
        expect(parsedPayout.receiver).toEqualAddress(depositor.address)
        expect(parsedPayout.payloadToForward!!).toEqualCell(payloadOnFailure)
    })
})
