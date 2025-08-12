// source map for contracts paths,
// entrypoint is 'sources/contracts/...'
export const DEX_SOURCES = {
    "ton-vault": "sources/contracts/ton-vault.tolk",
    "liquidity-deposit": "sources/contracts/liquidity-deposit.tolk",
    "amm-pool": "sources/contracts/amm-pool.tolk",
    "lp-jetton-wallet": "sources/contracts/lp-jettons/lp-jetton-wallet.tolk",
    "jetton-vault": "sources/contracts/jetton-vault.tolk",
    "sharded-jetton-minter": "sources/contracts/sharded-jettons/jetton-minter-contract.tolk",
    "sharded-jetton-wallet": "sources/contracts/sharded-jettons/jetton-wallet-contract.tolk",
}

export type ContractName = keyof typeof DEX_SOURCES
