# Super DCA Swap
_forked from [https://github.com/0ximmeas/univ4-swap-walkthrough](https://github.com/0ximmeas/univ4-swap-walkthrough)_

This is a simple contract that allows you to swap between two tokens using the Uniswap V4 protocol.

The contract supports `swapExactInputSingle` using a `PoolKey` and `swapExactInput` using a `PathKey` array.

## Usage
This contract is designed to be intergrated with inside of the Super DCA Pool contracts. It can be integrated in Solidity as follows:

1. One time token approval for the contract to spend the token.
```solidity
swapContract.approveTokenWithPermit2(tokenAddress, amount, expiration);
```
2. Transfer the token to the contract and call the swap function (must be one transaction)
```solidity
inputToken.transfer(address(swapContract), amountIn);
swapContract.swapExactInputSingle(poolKey, zeroForOne, amountIn, minAmountOut, receiver);
```
**Important**: The transfer and swap must be in the same call (e.g., inside a multi-call transaction).

## Deployed Contracts

| Network | Address |
|---------|---------|
| Base Sepolia | [0x0000000000000000000000000000000000000000](https://sepolia.basescan.org/address/0x0000000000000000000000000000000000000000) |
| Unichain Sepolia | [0x4779F177d595ad1Dee69034a58A668fc6116aF96.](https://unichain-sepolia.blockscout.com/address/0x4779F177d595ad1Dee69034a58A668fc6116aF96) |


### Build
```shell
$ forge build
```

### Test
```shell
$ forge test
```
