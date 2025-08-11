// source map for contracts paths,
// entrypoint is 'sources/contracts/...'
export const DEX_SOURCES = {
    "ton-vault": "sources/contracts/vaults/ton-vault.tolk",
}

export type ContractName = keyof typeof DEX_SOURCES
