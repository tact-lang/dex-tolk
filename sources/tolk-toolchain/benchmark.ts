//  SPDX-License-Identifier: MIT
//  Copyright © 2025 TON Studio

import crypto from "crypto"

// Mock randomBytes to return deterministic values for benchmarking
crypto.randomBytes = ((size: number) => Buffer.alloc(size, 0x42)) as typeof crypto.randomBytes

import {
    generateResults,
    getStateSizeForAccount,
    getUsedGasInternal,
    printBenchmarkTable,
} from "../utils/gas"
import benchmarkResults from "./dex.json"
import {Blockchain} from "@ton/sandbox"
import {toNano} from "@ton/core"
import {findTransactionRequired, flattenTransaction, randomAddress} from "@ton/test-utils"
import {createTonJettonAmmPool} from "../utils/environment-tolk"

export const runAddLiquidity = async () => {
    const blockchain = await Blockchain.create()

    const {vaultB, vaultA} = await createTonJettonAmmPool(blockchain)

    await vaultA.deploy()
    await vaultB.deploy()

    const amountA = toNano(1)
    const amountB = toNano(2)

    const addLiquidityWithDeployTonVault = await vaultA.addLiquidity(
        randomAddress(0),
        amountA,
        null,
        null,
        0n,
        0n,
        {
            id: 1n,
            otherVaultAddress: vaultB.vault.address,
            otherAmount: amountB,
        },
    )

    // external -> v4 -> ton vault -> liq proxy
    const gasUsedTonLp = getUsedGasInternal(addLiquidityWithDeployTonVault.transactions.slice(1, 3))

    const returnFundsTx = flattenTransaction(
        findTransactionRequired(addLiquidityWithDeployTonVault.transactions, {
            from: vaultA.vault.address,
            success: true,
            deploy: true,
        }),
    )

    const liquidityDepositContractAddress = returnFundsTx.to!

    // external -> v4 -> user jw -> vault jw -> vault -> liq proxy ->
    // -> pool -> user lp jw
    const addLiqJettonWithPoolNotify = await vaultB.addLiquidity(
        liquidityDepositContractAddress,
        amountB,
    )

    const gasUsedJettonLp = getUsedGasInternal(addLiqJettonWithPoolNotify.transactions.slice(3, 7))

    return gasUsedTonLp + gasUsedJettonLp
}

export const runSwap = async () => {
    const blockchain = await Blockchain.create()

    const {ammPool, vaultA, vaultB, initWithLiquidity, swap} =
        await createTonJettonAmmPool(blockchain)

    // deploy liquidity deposit contract
    const initialRatio = 2n

    const amountA = toNano(1)
    const amountB = amountA * initialRatio // 1 a == 2 b ratio

    const depositor = vaultB.treasury.walletOwner

    await initWithLiquidity(depositor, amountA, amountB)

    const amountToSwap = 10n
    const expectedOutput = await ammPool.getExpectedOut(vaultA.vault.address, amountToSwap)

    const swapResult = await swap(amountToSwap, "vaultA", expectedOutput)

    // external -> v4 -> ton vault -> pool -> jet vault -> vault jw ->
    // -> user jw
    const tonToJettonGasUsed = getUsedGasInternal(swapResult.transactions.slice(1, 4))

    const expectedOutputTon = await ammPool.getExpectedOut(vaultB.vault.address, amountToSwap)
    const swapResultJetton = await swap(amountToSwap, "vaultB", expectedOutputTon)

    // external -> v4 -> user jw -> vault jw -> vault -> pool ->
    // -> ton vault -> user
    const jettonToTonGasUsed = getUsedGasInternal(swapResultJetton.transactions.slice(3, 6))

    return {
        tonToJettonGasUsed,
        jettonToTonGasUsed,
    }
}

export const runGetSizes = async () => {
    const blockchain = await Blockchain.create()

    const {ammPool, vaultA, vaultB, initWithLiquidity} = await createTonJettonAmmPool(blockchain)

    // deploy liquidity deposit contract
    const initialRatio = 2n

    const amountA = toNano(1)
    const amountB = amountA * initialRatio // 1 a == 2 b ratio

    const depositor = vaultB.treasury.walletOwner

    await initWithLiquidity(depositor, amountA, amountB)

    return {
        jettonVault: await getStateSizeForAccount(blockchain, vaultB.vault.address),
        tonVault: await getStateSizeForAccount(blockchain, vaultA.vault.address),
        pool: await getStateSizeForAccount(blockchain, ammPool.address),
    }
}

const assertWasm = (left: number, right: number) => {
    if (left !== right) {
        console.error(`${left} != ${right}`)
        process.exit(-1)
    }
}

const main = async () => {
    const results = generateResults(benchmarkResults)
    const expectedResult = results.at(-1)!

    const liquidityResult = await runAddLiquidity()
    const swapResults = await runSwap()

    assertWasm(liquidityResult, expectedResult.gas["liquidity"])
    assertWasm(swapResults.tonToJettonGasUsed, expectedResult.gas["ton-swap"])
    assertWasm(swapResults.jettonToTonGasUsed, expectedResult.gas["jetton-swap"])

    const sizes = await runGetSizes()

    assertWasm(sizes.tonVault.bits, expectedResult.size["ton-vault-bits"])
    assertWasm(sizes.tonVault.cells, expectedResult.size["ton-vault-cells"])
    assertWasm(sizes.jettonVault.bits, expectedResult.size["jetton-vault-bits"])
    assertWasm(sizes.jettonVault.cells, expectedResult.size["jetton-vault-cells"])
    assertWasm(sizes.pool.bits, expectedResult.size["pool-bits"])
    assertWasm(sizes.pool.cells, expectedResult.size["pool-cells"])

    assertWasm(
        liquidityResult + swapResults.jettonToTonGasUsed + swapResults.tonToJettonGasUsed,
        expectedResult.summary,
    )

    if (process.env.PRINT_TABLE === "true") {
        printBenchmarkTable(results, {
            implementationName: "Tolk dex",
            printMode: "full",
        })
    }
}

if (require.main === module) {
    void main()
}
