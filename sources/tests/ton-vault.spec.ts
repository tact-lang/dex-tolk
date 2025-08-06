//  SPDX-License-Identifier: MIT
//  Copyright © 2025 TON Studio

import {Blockchain, internal} from "@ton/sandbox"
import {createJetton, createTonVault} from "../utils/environment-tolk"
import {beginCell, toNano} from "@ton/core"
import {findTransactionRequired, flattenTransaction, randomAddress} from "@ton/test-utils"
import {randomInt} from "node:crypto"
import {loadPayoutFromTonVault} from "../output/DEX_TonVault"
import {sortAddresses} from "../utils/deployUtils"
import {Op} from "../tolk-wrappers/lp-jettons/JettonConstants"
import {DexErrors, DexOpcodes} from "../tolk-wrappers/DexConstants"
import {createAmmPoolContract, createTonVaultContract} from "../tolk-toolchain/generator"

describe("TON Vault", () => {
    test("Jettons are returned if sent to TON Vault", async () => {
        const blockchain = await Blockchain.create()
        const vaultSetup = await createTonVault(blockchain)

        const _ = await vaultSetup.deploy()
        const mockActionPayload = beginCell().storeStringTail("Random payload").endCell()

        const jetton = await createJetton(blockchain)
        const initialBalance = await jetton.wallet.getJettonBalance()
        const numberOfJettons = BigInt(randomInt(0, 100000000000))

        const sendResult = await jetton.transfer(
            vaultSetup.vault.address,
            numberOfJettons,
            mockActionPayload,
        )

        const toVaultTx = flattenTransaction(
            findTransactionRequired(sendResult.transactions, {
                to: vaultSetup.vault.address,
                op: Op.transfer_notification,
                success: true, // Because commit was called
                exitCode: DexErrors.JETTONS_SENT_TO_TON_VAULT,
            }),
        )

        expect(sendResult.transactions).toHaveTransaction({
            from: vaultSetup.vault.address,
            to: toVaultTx.from,
            op: Op.transfer,
            success: true,
        })
        const finalJettonBalance = await jetton.wallet.getJettonBalance()
        expect(finalJettonBalance).toEqual(initialBalance)
    })
    test("TON Vault successfully transfers swap payload", async () => {
        const blockchain = await Blockchain.create()

        const tonVaultContract = await createTonVaultContract()
        const openedTonVault = blockchain.openContract(tonVaultContract)

        const deployer = await blockchain.treasury("deployer")

        // Deploy contract
        const deployRes = await openedTonVault.sendDeploy(deployer.getSender(), toNano(0.1))
        expect(deployRes.transactions).toHaveTransaction({
            on: tonVaultContract.address,
            deploy: true,
        })

        const otherVaultAddress = randomAddress(0)
        const sortedAddresses = sortAddresses(tonVaultContract.address, otherVaultAddress, 0n, 0n)
        const randomAmmPool = await createAmmPoolContract(
            sortedAddresses.lower,
            sortedAddresses.higher,
        )
        const tonVaultObject = await blockchain.getContract(tonVaultContract.address)

        const randomReceiver = randomAddress(0)
        const payloadToForward = beginCell()
            .storeStringTail("Random quite big payload. User can encode anything here")
            .endCell()

        const res = await tonVaultObject.receiveMessage(
            internal({
                from: randomAmmPool.address,
                to: tonVaultContract.address,
                value: toNano(0.1),
                body: beginCell()
                    .storeUint(DexOpcodes.PayoutFromPool, 32)
                    .storeAddress(otherVaultAddress)
                    .storeCoins(0)
                    .storeAddress(randomReceiver)
                    .storeMaybeRef(payloadToForward)
                    .endCell(),
            }),
        )

        const flatTx = flattenTransaction(res)

        expect(flatTx.exitCode).toEqual(0)
        expect(flatTx.actionResultCode).toEqual(0)
        expect(res.outMessagesCount).toEqual(1)

        const payoutBody = res.outMessages.get(0)?.body

        expect(payoutBody).toBeDefined()

        const parsedPayout = loadPayoutFromTonVault(payoutBody!.beginParse())

        expect(parsedPayout.$$type).toEqual("PayoutFromTonVault")
        expect(parsedPayout.body).toEqualCell(payloadToForward)
    })
})
