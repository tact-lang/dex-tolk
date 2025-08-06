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
    // TODO: add tests for all combinations of pools (with it.each, it should be the same)
    test("should increase pool reserves by correct amount", async () => {
        const blockchain = await Blockchain.create()

        const {ammPool, vaultB, isSwapped, initWithLiquidity} = await createPool(blockchain)

        const initialRatio = 7n

        const amountARaw = toNano(1)
        const amountBRaw = amountARaw * initialRatio // 1 a == 2 b ratio

        const amountA = isSwapped ? amountARaw : amountBRaw
        const amountB = isSwapped ? amountBRaw : amountARaw

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
        const leftSide = vaultsAndReserves.lowerAmount
        const rightSide = vaultsAndReserves.higherAmount

        expect(leftSide).toEqual(expectedLpAmount.reserveA)
        expect(rightSide).toEqual(expectedLpAmount.reserveB)
    })

    test("should increase pool reserves by correct amount with revert", async () => {
        const blockchain = await Blockchain.create()

        const {ammPool, vaultB, isSwapped, initWithLiquidity} = await createPool(blockchain)

        const initialRatio = 7n

        const amountARaw = toNano(1)
        const amountBRaw = amountARaw * initialRatio // 1 a == 2 b ratio

        const amountA = isSwapped ? amountARaw : amountBRaw
        const amountB = isSwapped ? amountBRaw : amountARaw

        const depositor = vaultB.treasury.walletOwner

        const {getLpWallet} = await initWithLiquidity(depositor, amountA, amountB)
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

        const amountABadRatio = isSwapped ? amountABadRatioRaw : amountBBadRatioRaw
        const amountBBadRatio = isSwapped ? amountBBadRatioRaw : amountABadRatioRaw

        // second add
        await initWithLiquidity(depositor, amountABadRatio, amountBBadRatio)

        const lpBalanceAfterSecondLiq = await depositorLpWallet.getJettonBalance()

        const expectedLpAmountSecondTime = calculateLiquidityProvisioning(
            reserveABefore,
            reserveBBefore,
            amountABadRatio,
            amountBBadRatio,
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
        const vaultsAndReservesAfter = await ammPool.getVaultsAndReserves()

        expect(vaultsAndReservesAfter.lowerAmount).toEqual(expectedLpAmountSecondTime.reserveA)
        expect(vaultsAndReservesAfter.higherAmount).toEqual(expectedLpAmountSecondTime.reserveB)
    })

    test("should follow math across multiple liquidity additions", async () => {
        const blockchain = await Blockchain.create()

        const {ammPool, vaultB, isSwapped, initWithLiquidity} = await createPool(blockchain)

        let lpAmount = 0n
        const depositor = vaultB.treasury.walletOwner

        const getReserves = async () => {
            try {
                const vaultsAndReservesAfter = await ammPool.getVaultsAndReserves()

                return {
                    left: vaultsAndReservesAfter.lowerAmount,
                    right: vaultsAndReservesAfter.higherAmount,
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

            const amountA = isSwapped ? amountARaw : amountBRaw
            const amountB = isSwapped ? amountBRaw : amountARaw

            const {left: reserveABefore, right: reserveBBefore} = await getReserves()

            const {getLpWallet} = await initWithLiquidity(depositor, amountA, amountB)
            const depositorLpWallet = await getLpWallet()

            const mintedTotal = await depositorLpWallet.getJettonBalance()
            const lpAmountMinted = mintedTotal === lpAmount ? lpAmount : mintedTotal - lpAmount

            const expectedLpAmount = calculateLiquidityProvisioning(
                reserveABefore,
                reserveBBefore,
                amountA,
                amountB,
                0n,
                0n,
                lpAmount,
            )

            // check that first liquidity deposit was successful
            // +-1 nano bound checks
            expect(lpAmountMinted).toBeGreaterThanOrEqual(expectedLpAmount.lpTokens - 1n)
            expect(lpAmountMinted).toBeLessThanOrEqual(expectedLpAmount.lpTokens + 1n)
            // check that pool reserves are correct
            const vaultsAndReservesAfter = await ammPool.getVaultsAndReserves()

            expect(vaultsAndReservesAfter.lowerAmount).toEqual(expectedLpAmount.reserveA)
            expect(vaultsAndReservesAfter.higherAmount).toEqual(expectedLpAmount.reserveB)

            lpAmount = mintedTotal
        }
    })

    test("should withdraw correct liquidity amount", async () => {
        const blockchain = await Blockchain.create()

        const {ammPool, vaultB, isSwapped, initWithLiquidity} = await createPool(blockchain)

        const initialRatio = 7n

        const amountARaw = toNano(1)
        const amountBRaw = amountARaw * initialRatio // 1 a == 2 b ratio

        const amountA = isSwapped ? amountARaw : amountBRaw
        const amountB = isSwapped ? amountBRaw : amountARaw

        const depositor = vaultB.treasury.walletOwner

        const {getLpWallet, withdrawLiquidity} = await initWithLiquidity(
            depositor,
            amountA,
            amountB,
        )

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

        const vaultsAndReservesAfter = await ammPool.getVaultsAndReserves()

        expect(vaultsAndReservesAfter.lowerAmount).toEqual(expectedBurnResult.reserveA)
        expect(vaultsAndReservesAfter.higherAmount).toEqual(expectedBurnResult.reserveB)

        const lpBalanceAfterWithdraw = await depositorLpWallet.getJettonBalance()
        expect(lpBalanceAfterWithdraw).toEqual(0n)
    })

    test("should reject withdraw if amount is less then min", async () => {
        const blockchain = await Blockchain.create()

        const {ammPool, vaultB, isSwapped, initWithLiquidity} = await createPool(blockchain)

        const initialRatio = 7n

        const amountARaw = toNano(1)
        const amountBRaw = amountARaw * initialRatio // 1 a == 2 b ratio

        const amountA = isSwapped ? amountARaw : amountBRaw
        const amountB = isSwapped ? amountBRaw : amountARaw

        const depositor = vaultB.treasury.walletOwner

        const {getLpWallet, withdrawLiquidity} = await initWithLiquidity(
            depositor,
            amountA,
            amountB,
        )

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

        const expectedBurnResultSuccess = calculateLiquidityWithdraw(
            expectedLpAmount.reserveA,
            expectedLpAmount.reserveB,
            lpBalanceAfterFirstLiq,
            0n,
            0n,
            lpBalanceAfterFirstLiq,
        )

        // send burn with value more than min, it should fail
        const result = await withdrawLiquidity(
            lpBalanceAfterFirstLiq,
            expectedBurnResultSuccess.amountA + 1n,
            expectedBurnResultSuccess.amountB + 1n,
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
            exitCode: AmmPool.errors["Pool: Couldn't pay left more than asked"],
        })

        // same as before
        const vaultsAndReservesAfter = await ammPool.getVaultsAndReserves()

        expect(vaultsAndReservesAfter.lowerAmount).toEqual(expectedLpAmount.reserveA)
        expect(vaultsAndReservesAfter.higherAmount).toEqual(expectedLpAmount.reserveB)

        // bounces
        const lpBalanceAfterWithdraw = await depositorLpWallet.getJettonBalance()
        expect(lpBalanceAfterWithdraw).toEqual(lpBalanceAfterFirstLiq)
    })
})
