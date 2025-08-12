# OpenDeFi Library: Decentralized Exchange in Tolk

This repo contains source code for Ton Dex contracts in Tolk and tests/infrastructure for them.

Tests, core logic and environment for this project are reused from the [T-Dex](https://github.com/tact-lang/dex), similar project written in Tact. Although, there are some semantic changes, to adapt existing interfaces to Tolk language patterns and idioms.

## Project Goals

- Build a fully open-source decentralized exchange (DEX)
- Keep transaction costs low with efficient smart contract design
- Show how to build complex smart contracts using Tolk
- Demonstrate safe patterns for working with Jettons
- Explore Tolk language features in a real production system

This project aims to show core TON smart contract development principles and serve as a foundation for other Jetton-based protocols. We also want to explore how Tolk works for building complex multi-contract systems and what coding patterns and idioms work best.

## Project Scope

We follow somewhat common Dex architecture and math - [Constant Product Formula Market Maker](https://en.wikipedia.org/wiki/Constant_function_market_maker) compatible with [Uniswap V2](https://docs.uniswap.org/whitepaper.pdf). There is no "protocol fee" implemented since the project is open source, only LP providers fee in pools (however it should be possible to add one).

Dex allows cross-pool and exact-out swaps and implements asset-abstraction model, meaning that the protocol could be extended to allow swaps between any kinds of assets.

## How-to and dev docs

Check these docs to learn about how Dex works, its semantics and how to integrate with it.

- [How to swap on Dex](./dev-docs/swap.md)
- [How to manage liquidity](./dev-docs/liquidity.md)
- How to work with Factory, TODO
- How to create new pool and vaults, TODO

## Project Setup and Development

To start working, install all dependencies:

```shell
yarn install
```

Build the contracts:

```shell
yarn build:tolk
```

Other useful commands:

Run tests:

```shell
yarn test
```

Lint the code:

```shell
yarn lint
```

Format the code:

```shell
yarn fmt
```

## Testing

The project uses Jest for testing. Tests are located in the `sources/tests` directory and cover various aspects of the T-Dex functionality:

- `amm-pool.spec.ts` - Tests for the AMM Pool functionality
- `liquidity-deposit.spec.ts` - Tests for liquidity deposit process
- `liquidity-payloads.spec.ts` - Tests for payload handling in liquidity operations
- `swap-payloads.spec.ts` - Tests for payload handling in swap operations

To run all tests:

```shell
yarn test
```

## Contract Configuration

TODO: describe Tolk pipeline

## License

[MIT](./LICENSE)
