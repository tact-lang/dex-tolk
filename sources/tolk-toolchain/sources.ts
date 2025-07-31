// source map for contracts paths,
// entrypoint is 'sources/contracts/...'
export const DEX_SOURCES = {
    "ton-vault": "sources/contracts/tolk/ton-vault.tolk",
    "liquidity-deposit": "sources/contracts/tolk/liquidity-deposit.tolk",
    "amm-pool": "sources/contracts/tolk/amm-pool.tolk",
    "lp-jetton-wallet": "sources/contracts/tolk/lp-jettons/lp-jetton-wallet.tolk",
    "jetton-vault": "sources/contracts/tolk/jetton-vault.tolk",
}

export type ContractName = keyof typeof DEX_SOURCES
