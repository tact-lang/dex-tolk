//  SPDX-License-Identifier: MIT
//  Copyright © 2025 TON Studio

import {createInterface} from "readline/promises"
import benchmarkResults from "../tolk-toolchain/dex.json"

import {writeFile} from "fs/promises"
import {join} from "path"
import {generateResults, printBenchmarkTable} from "../utils/gas"
import chalk from "chalk"
import {runAddLiquidity, runGetSizes, runSwap} from "./benchmark"

const readInput = async () => {
    const readline = createInterface({
        input: process.stdin,
        output: process.stdout,
    })

    const label = await readline.question(`Benchmark label: `)
    const prNumber = await readline.question("PR number: ")

    readline.close()

    return {label, prNumber}
}

const main = async () => {
    const isUpdate = process.env.UPDATE === "true"

    const expectedResult = benchmarkResults.results.at(-1)!

    const data = isUpdate
        ? {label: expectedResult.label, prNumber: expectedResult.pr}
        : await readInput()

    const liquidityResult = await runAddLiquidity()
    const swapResults = await runSwap()

    const sizes = await runGetSizes()

    const newBenchmarkResult = {
        label: data.label,
        pr: data.prNumber,
        gas: {
            liquidity: liquidityResult.toString(),
            "ton-swap": swapResults.tonToJettonGasUsed.toString(),
            "jetton-swap": swapResults.jettonToTonGasUsed.toString(),
        },
        size: {
            "ton-vault-bits": sizes.tonVault.bits.toString(),
            "ton-vault-cells": sizes.tonVault.cells.toString(),
            "jetton-vault-bits": sizes.jettonVault.bits.toString(),
            "jetton-vault-cells": sizes.jettonVault.cells.toString(),
            "pool-bits": sizes.pool.bits.toString(),
            "pool-cells": sizes.pool.cells.toString(),
        },
        summary: String(
            liquidityResult + swapResults.jettonToTonGasUsed + swapResults.tonToJettonGasUsed,
        ),
    }

    if (isUpdate) {
        console.log(chalk.yellow("Updated benchmark results!\n"))
        expectedResult.gas = newBenchmarkResult.gas
        expectedResult.summary = newBenchmarkResult.summary
        expectedResult.size = newBenchmarkResult.size
    } else {
        console.log(chalk.yellow("Added new entry to benchmark results!\n"))
        benchmarkResults.results.push(newBenchmarkResult)
    }

    const results = generateResults(benchmarkResults)
    printBenchmarkTable(results, {
        implementationName: "Tolk dex",
        printMode: "last-diff",
    })

    await writeFile(
        join(__dirname, "../tolk-toolchain/dex.json"),
        JSON.stringify(benchmarkResults, null, 4) + "\n",
    )
}

void main()
