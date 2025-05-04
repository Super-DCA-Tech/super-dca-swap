# Super DCA Swap
_forked from [https://github.com/0ximmeas/univ4-swap-walkthrough](https://github.com/0ximmeas/univ4-swap-walkthrough)_

This is a simple contract that allows you to swap between two tokens using the Uniswap V4 protocol.

The contract supports `swapExactInputSingle` using a `PoolKey` and `swapExactInput` using a `PathKey` array.

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
