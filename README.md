# Super DCA Swap
_forked from [https://github.com/0ximmeas/univ4-swap-walkthrough](https://github.com/0ximmeas/univ4-swap-walkthrough)_

This is a simple contract that allows you to swap between two tokens using the Uniswap V4 protocol.

The contract supports `swapExactInputSingle` using a `PoolKey` and `swapExactInput` using a `PathKey` array.

## Usage
This contract is designed to be used as a mixin contract for the Super DCA Pool contracts and other contracts that need to swap tokens through Uniswap V4.

It implements simpler methods for swapping tokens through Uniswap V4 by encoding the Universal Router command and actions into a single call. Those methods are:

* `swapExactInputSingle`
* `swapExactInput`

These may look familiar to users of the Uniswap V3 periphery. They work the same way only using structs from Uniswap V4. 

### Integration with Super DCA Pool

The Super DCA Pool contract is designed to be used as a mixin contract for the Super DCA Pool contracts.

```solidity 
contract SuperDCAPool is SuperDCASwap {
    constructor(address _poolManager, address _universalRouter, address _permit2) SuperDCASwap(_poolManager, _universalRouter, _permit2) {}
}
```



### Build
```shell
$ forge build
```

### Test
```shell
$ forge test
```
