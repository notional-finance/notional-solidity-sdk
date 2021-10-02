# Notional V2 Solidity SDK

This SDK is geared towards developers who want to integrate with Notional V2 on chain. The repository currently uses [ETH Brownie](https://github.com/eth-brownie/brownie) as the smart contract development platform but can be adapted to support Truffle or Hardhat as well. This repo includes Notional V2 interfaces, contract addresses and some encoding utilities that make interacting with Notional V2 easier.

WARNING: example contracts in this repository may or may not have been audited. These examples are provided without warranty or guarantee. Some of these examples allow for arbitrary code execution which opens the door for many potential attack vectors.

## Getting Started

The easiest way to develop and test is to use the Notional V2 docker image. This will spin up a local ganache blockchain with Notional V2 and Compound Finance smart contracts deployed and a set of mock tokens. Contract addresses for mainnet and kovan can be found in the corresponding json files.

You can also get the contract addresses via `contracts/lib/Addresses.sol` which will has address constants for various chains.

## Types

Notional V2 data types can be found in `Types.sol`. `EncodeDecode.sol` provides library methods for decoding and encoding some tightly packed types.

## Helpers

- Sell all fCash assets

## Examples

- ifCash Liquidator
- Flash Liquidator
- Debt Settler
- Swap Compound to Notional
