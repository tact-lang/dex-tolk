//  SPDX-License-Identifier: MIT
//  Copyright © 2025 TON Studio

import {toNano} from "@ton/core"
import {Blockchain} from "@ton/sandbox"
import {createJettonAmmPool, createTonJettonAmmPool} from "../utils/environment-tolk"
// eslint-disable-next-line
import {SendDumpToDevWallet} from "@tondevwallet/traces"
import {calculateLiquidityProvisioning, calculateLiquidityWithdraw} from "../utils/liquidityMath"
import {AmmPool} from "../output/DEX_AmmPool"
import {Op} from "../tolk-wrappers/lp-jettons/JettonConstants"

describe.each([
    {
        name: "Jetton->Jetton",
        createPool: createJettonAmmPool,
    },
    {
        name: "TON->Jetton",
        createPool: createTonJettonAmmPool,
    },
])("Liquidity math for $name", ({createPool}) => {
    test("should increase pool reserves by correct amount", async () => {
        const blockchain = await Blockchain.create()

        const {ammPool, vaultB, isSwapped, initWithLiquidity} = await createPool(blockchain)

        const initialRatio = 7n

        const amountARaw = toNano(1)
        const amountBRaw = amountARaw * initialRatio // 1 a == 2 b ratio

        const amountA = amountBRaw
        const amountB = amountARaw

        const depositor = vaultB.treasury.walletOwner

        const {getLpWallet} = await initWithLiquidity(depositor, amountA, amountB)
        const depositorLpWallet = await getLpWallet()

        const lpBalanceAfterFirstLiq = await depositorLpWallet.getJettonBalance()

        const expectedLpAmount = calculateLiquidityProvisioning(
            0n,
            0n,
            amountA,
            amountB,
            0n,
            0n,
            0n,
        )

        // check that first liquidity deposit was successful
        expect(lpBalanceAfterFirstLiq).toEqual(expectedLpAmount.lpTokens)
        // check that pool reserves are correct
        const vaultsAndReserves = await ammPool.getVaultsAndReserves()
        expect(vaultsAndReserves.lowerAmount).toEqual(
            isSwapped ? expectedLpAmount.reserveB : expectedLpAmount.reserveA,
        )
        expect(vaultsAndReserves.higherAmount).toEqual(
            isSwapped ? expectedLpAmount.reserveA : expectedLpAmount.reserveB,
        )
    })

    test("should increase pool reserves by correct amount with revert", async () => {
        const blockchain = await Blockchain.create()

        const {ammPool, vaultB, isSwapped, initWithLiquidity} = await createPool(blockchain)

        const initialRatio = 7n

        const amountARaw = toNano(1)
        const amountBRaw = amountARaw * initialRatio // 1 a == 2 b ratio

        const depositor = vaultB.treasury.walletOwner

        const {getLpWallet} = await initWithLiquidity(depositor, amountARaw, amountBRaw)
        const depositorLpWallet = await getLpWallet()

        const lpBalanceAfterFirstLiq = await depositorLpWallet.getJettonBalance()
        // check that first liquidity deposit was successful
        expect(lpBalanceAfterFirstLiq).toBeGreaterThan(0n)

        const vaultsAndReserves = await ammPool.getVaultsAndReserves()
        const reserveABefore = vaultsAndReserves.lowerAmount
        const reserveBBefore = vaultsAndReserves.higherAmount

        // change value a little so it won't be equal to reserveA
        const amountABadRatioRaw = toNano(1.1)
        const amountBBadRatioRaw = amountABadRatioRaw * initialRatio * 5n // wrong ratio

        // second add
        await initWithLiquidity(depositor, amountABadRatioRaw, amountBBadRatioRaw)

        const lpBalanceAfterSecondLiq = await depositorLpWallet.getJettonBalance()

        const expectedLpAmountSecondTime = calculateLiquidityProvisioning(
            isSwapped ? reserveBBefore : reserveABefore,
            isSwapped ? reserveABefore : reserveBBefore,
            amountABadRatioRaw,
            amountBBadRatioRaw,
            0n,
            0n,
            lpBalanceAfterFirstLiq,
        )

        // since we have same depositor
        const lpAmountMinted = lpBalanceAfterSecondLiq - lpBalanceAfterFirstLiq

        // something was minted
        expect(lpAmountMinted).toBeGreaterThan(0n)
        expect(lpAmountMinted).toEqual(expectedLpAmountSecondTime.lpTokens)

        // check that pool reserves are correct
        const reservesAfter = await ammPool.getVaultsAndReserves()
        expect(reservesAfter.lowerAmount).toEqual(
            isSwapped ? expectedLpAmountSecondTime.reserveB : expectedLpAmountSecondTime.reserveA,
        )
        expect(reservesAfter.higherAmount).toEqual(
            isSwapped ? expectedLpAmountSecondTime.reserveA : expectedLpAmountSecondTime.reserveB,
        )
    })

    test("should follow math across multiple liquidity additions", async () => {
        const blockchain = await Blockchain.create()

        const {ammPool, vaultB, isSwapped, initWithLiquidity} = await createPool(blockchain)

        let lpAmount = 0n
        const depositor = vaultB.treasury.walletOwner

        const getReserves = async () => {
            try {
                const reserves = await ammPool.getVaultsAndReserves()
                return {
                    left: reserves.lowerAmount,
                    right: reserves.higherAmount,
                }
            } catch (error) {
                return {
                    left: 0n,
                    right: 0n,
                }
            }
        }

        const random = (min: number, max: number) =>
            Math.floor(Math.random() * (max - min + 1)) + min

        for (let index = 0; index < 10; index++) {
            const initialRatio = BigInt(random(1, 10)) // Random ratio between 1 and 10

            const amountARaw = BigInt(random(1, 1000))
            const amountBRaw = amountARaw * initialRatio

            const {left: reserveABefore, right: reserveBBefore} = await getReserves()

            const {getLpWallet} = await initWithLiquidity(depositor, amountARaw, amountBRaw)
            const depositorLpWallet = await getLpWallet()

            const mintedTotal = await depositorLpWallet.getJettonBalance()
            const lpAmountMinted = mintedTotal === lpAmount ? lpAmount : mintedTotal - lpAmount

            const expectedLpAmount = calculateLiquidityProvisioning(
                isSwapped ? reserveBBefore : reserveABefore,
                isSwapped ? reserveABefore : reserveBBefore,
                amountARaw,
                amountBRaw,
                0n,
                0n,
                lpAmount,
            )

            // check that first liquidity deposit was successful
            // +-1 nano bound checks
            expect(lpAmountMinted).toBeGreaterThanOrEqual(expectedLpAmount.lpTokens - 1n)
            expect(lpAmountMinted).toBeLessThanOrEqual(expectedLpAmount.lpTokens + 1n)
            // check that pool reserves are correct
            const reserves = await ammPool.getVaultsAndReserves()

            expect(reserves.lowerAmount).toEqual(
                isSwapped ? expectedLpAmount.reserveB : expectedLpAmount.reserveA,
            )
            expect(reserves.higherAmount).toEqual(
                isSwapped ? expectedLpAmount.reserveA : expectedLpAmount.reserveB,
            )

            lpAmount = mintedTotal
        }
    })

    test("should withdraw correct liquidity amount", async () => {
        const blockchain = await Blockchain.create()

        const {ammPool, vaultB, isSwapped, initWithLiquidity} = await createPool(blockchain)

        const initialRatio = 7n

        const amountARaw = toNano(1)
        const amountBRaw = amountARaw * initialRatio // 1 a == 2 b ratio

        const depositor = vaultB.treasury.walletOwner

        const {getLpWallet, withdrawLiquidity} = await initWithLiquidity(
            depositor,
            amountARaw,
            amountBRaw,
        )
        const depositorLpWallet = await getLpWallet()

        const lpBalanceAfterFirstLiq = await depositorLpWallet.getJettonBalance()

        const expectedLpAmount = calculateLiquidityProvisioning(
            0n,
            0n,
            amountARaw,
            amountBRaw,
            0n,
            0n,
            0n,
        )

        // send burn and check that amount is correct
        await withdrawLiquidity(lpBalanceAfterFirstLiq, 0n, 0n, 0n, null)

        const expectedBurnResult = calculateLiquidityWithdraw(
            expectedLpAmount.reserveA,
            expectedLpAmount.reserveB,
            lpBalanceAfterFirstLiq,
            0n,
            0n,
            lpBalanceAfterFirstLiq,
        )

        const reserves = await ammPool.getVaultsAndReserves()
        expect(reserves.lowerAmount).toEqual(
            isSwapped ? expectedBurnResult.reserveB : expectedBurnResult.reserveA,
        )
        expect(reserves.higherAmount).toEqual(
            isSwapped ? expectedBurnResult.reserveA : expectedBurnResult.reserveB,
        )

        const lpBalanceAfterWithdraw = await depositorLpWallet.getJettonBalance()
        expect(lpBalanceAfterWithdraw).toEqual(0n)
    })

    test("should reject withdraw if amount is less then min", async () => {
        const blockchain = await Blockchain.create()

        const {ammPool, vaultB, isSwapped, initWithLiquidity} = await createPool(blockchain)

        const initialRatio = 7n

        const amountARaw = toNano(1)
        const amountBRaw = amountARaw * initialRatio // 1 a == 2 b ratio

        const depositor = vaultB.treasury.walletOwner

        const {getLpWallet, withdrawLiquidity} = await initWithLiquidity(
            depositor,
            amountARaw,
            amountBRaw,
        )
        const depositorLpWallet = await getLpWallet()

        const lpBalanceAfterFirstLiq = await depositorLpWallet.getJettonBalance()

        const expectedLpAmount = calculateLiquidityProvisioning(
            0n,
            0n,
            amountARaw,
            amountBRaw,
            0n,
            0n,
            0n,
        )

        const expectedBurnResultSuccess = calculateLiquidityWithdraw(
            expectedLpAmount.reserveA,
            expectedLpAmount.reserveB,
            lpBalanceAfterFirstLiq,
            0n,
            0n,
            lpBalanceAfterFirstLiq,
        )

        const lowerBurnAmountMoreThan = isSwapped
            ? expectedBurnResultSuccess.amountB + 1n
            : expectedBurnResultSuccess.amountA + 1n

        const higherBurnAmountMoreThan = isSwapped
            ? expectedBurnResultSuccess.amountA + 1n
            : expectedBurnResultSuccess.amountB + 1n

        // send burn with value more than min, it should fail
        const result = await withdrawLiquidity(
            lpBalanceAfterFirstLiq,
            lowerBurnAmountMoreThan,
            higherBurnAmountMoreThan,
            0n,
            null,
        )

        const burnResultThatShouldFail = () =>
            calculateLiquidityWithdraw(
                expectedLpAmount.reserveA,
                expectedLpAmount.reserveB,
                lpBalanceAfterFirstLiq,
                expectedBurnResultSuccess.amountA + 1n,
                expectedBurnResultSuccess.amountB + 1n,
                lpBalanceAfterFirstLiq,
            )

        expect(burnResultThatShouldFail).toThrow("Insufficient A token amount")

        expect(result.transactions).toHaveTransaction({
            from: depositorLpWallet.address,
            to: ammPool.address,
            op: Op.burn_notification,
            success: false,
            // TODO: create error codes enum
            exitCode: AmmPool.errors["Pool: Couldn't pay left more than asked"],
        })

        // same as before
        const reserves = await ammPool.getVaultsAndReserves()
        expect(reserves.lowerAmount).toEqual(
            isSwapped ? expectedLpAmount.reserveB : expectedLpAmount.reserveA,
        )
        expect(reserves.higherAmount).toEqual(
            isSwapped ? expectedLpAmount.reserveA : expectedLpAmount.reserveB,
        )

        // bounces
        const lpBalanceAfterWithdraw = await depositorLpWallet.getJettonBalance()
        expect(lpBalanceAfterWithdraw).toEqual(lpBalanceAfterFirstLiq)
    })
})
