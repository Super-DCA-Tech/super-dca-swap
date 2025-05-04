// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Issues with importing the universal router solved with these imports
/// see: https://github.com/0ximmeas/univ4-swap-walkthrough
import { IUniversalRouter } from "src/external/IUniversalRouter.sol";
import { Commands } from "src/external/Commands.sol";

import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IV4Router } from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import { IPermit2 } from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SuperDCASwap {
    using StateLibrary for IPoolManager;

    IUniversalRouter public immutable router;
    IPoolManager public immutable poolManager;
    IPermit2 public immutable permit2;

    constructor(address _router, address _poolManager, address _permit2) {
        router = IUniversalRouter(_router);
        poolManager = IPoolManager(_poolManager);
        permit2 = IPermit2(_permit2);
    }

    function approveTokenWithPermit2(
        address token,
        uint160 amount,
        uint48 expiration
    ) external {
        IERC20(token).approve(address(permit2), type(uint256).max);
        permit2.approve(token, address(router), amount, expiration);
    }

    function swapExactInputSingle(
        PoolKey calldata key,
        bool zeroForOne,
        uint128 amountIn,
        uint128 minAmountOut
    ) external payable returns (uint256 amountOut) {
        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        // Determine the actual input and output tokens based on zeroForOne
        Currency inputCurrency = zeroForOne ? key.currency0 : key.currency1;
        Currency outputCurrency = zeroForOne ? key.currency1 : key.currency0;
        address inputTokenAddress = Currency.unwrap(inputCurrency);
        address outputTokenAddress = Currency.unwrap(outputCurrency);

        bool requireETHValue = inputTokenAddress == address(0);

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(inputCurrency, amountIn);
        params[2] = abi.encode(outputCurrency, minAmountOut);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        uint256 deadline = block.timestamp + 20;
        if (requireETHValue) {
            require(msg.value == amountIn, "Incorrect ETH amount");
            router.execute{value: amountIn}(commands, inputs, deadline);
        } else {
            require(msg.value == 0, "ETH not needed for this swap");
            router.execute(commands, inputs, deadline);
        }

        // Verify and return the output amount
        if (outputTokenAddress == address(0)) {
            amountOut = address(this).balance;
        } else {
            amountOut = IERC20(outputTokenAddress).balanceOf(address(this));
        }
        require(amountOut >= minAmountOut, "Insufficient output amount");
        return amountOut;
    }

    receive() external payable {}
}
