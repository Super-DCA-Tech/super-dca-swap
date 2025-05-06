// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Issues with importing the universal router solved with these imports
/// see: https://github.com/0ximmeas/univ4-swap-walkthrough
import {IUniversalRouter} from "src/external/IUniversalRouter.sol";
import {Commands} from "src/external/Commands.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {console} from "forge-std/console.sol";

contract SuperDCASwap {
    using StateLibrary for IPoolManager;

    IUniversalRouter public immutable ROUTER;
    IPoolManager public immutable POOL_MANAGER;
    IPermit2 public immutable PERMIT2;

    constructor(address _router, address _poolManager, address _permit2) {
        ROUTER = IUniversalRouter(_router);
        POOL_MANAGER = IPoolManager(_poolManager);
        PERMIT2 = IPermit2(_permit2);
    }

    function approveTokenWithPermit2(address token, uint160 amount, uint48 expiration) external {
        IERC20(token).approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(token, address(ROUTER), amount, expiration);
    }

    function swapExactInputSingle(PoolKey calldata key, bool zeroForOne, uint128 amountIn, uint128 minAmountOut)
        external
        payable
        returns (uint256 amountOut)
    {
        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

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
            ROUTER.execute{value: amountIn}(commands, inputs, deadline);
        } else {
            require(msg.value == 0, "ETH not needed for this swap");
            ROUTER.execute(commands, inputs, deadline);
        }

        // Verify and return the output amount
        if (outputTokenAddress == address(0)) {
            amountOut = address(this).balance;
            // Send ETH to the original caller
            (bool success, ) = msg.sender.call{value: amountOut}("");
            require(success, "ETH transfer failed");
        } else {
            amountOut = IERC20(outputTokenAddress).balanceOf(address(this));
            // Transfer ERC20 tokens to the original caller
            require(IERC20(outputTokenAddress).transfer(msg.sender, amountOut), "Token transfer failed");
        }
        require(amountOut >= minAmountOut, "Insufficient output amount");
        return amountOut;
    }

    receive() external payable {}

    /// @notice Swaps an exact amount of input tokens for as many output tokens as possible through a series of pools defined by a path.
    /// @param currencyIn The currency of the input token.
    /// @param path An array of PathKey structs defining the sequence of pools and intermediate tokens for the swap.
    /// @param amountIn The exact amount of `currencyIn` to be swapped.
    /// @param minAmountOut The minimum amount of the final output token that must be received for the swap not to revert.
    /// @return amountOut The amount of the final output token received.
    function swapExactInput(Currency currencyIn, PathKey[] calldata path, uint128 amountIn, uint128 minAmountOut)
        external
        payable
        returns (uint256 amountOut)
    {
        require(path.length > 0, "Path cannot be empty");

        // Encode the Universal Router command for a V4 swap
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // Encode the sequence of V4Router actions required for a multi-hop exact input swap
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN), // Perform the multi-hop swap defined by the path
            uint8(Actions.SETTLE_ALL), // Settle the debt of the input token created by the swap action
            uint8(Actions.TAKE_ALL) // Take the credit of the final output token created by the swap action
        );

        // Determine the final output currency from the last element in the path
        Currency outputCurrency = path[path.length - 1].intermediateCurrency;
        address inputTokenAddress = Currency.unwrap(currencyIn);
        address outputTokenAddress = Currency.unwrap(outputCurrency);

        // Check if the input token is native ETH to handle msg.value
        bool requireETHValue = inputTokenAddress == address(0);

        // Prepare the parameters for each action in the sequence
        bytes[] memory params = new bytes[](3);

        // Params[0]: Parameters for the SWAP_EXACT_IN action
        params[0] = abi.encode(
            IV4Router.ExactInputParams({
                currencyIn: currencyIn,
                path: path,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut // Although checked later, included for struct completeness
            })
        );

        // Params[1]: Parameters for the SETTLE_ALL action (settle the input currency)
        params[1] = abi.encode(currencyIn, amountIn);

        // Params[2]: Parameters for the TAKE_ALL action (take the final output currency)
        params[2] = abi.encode(outputCurrency, minAmountOut);

        // Combine actions and their corresponding parameters into the input for the V4_SWAP command
        inputs[0] = abi.encode(actions, params);

        // Set a deadline for the transaction
        uint256 deadline = block.timestamp + 20; // Using a short deadline (20 seconds)

        // Record balance before execution for ETH output calculation
        uint256 balanceBefore = address(this).balance;

        // Execute the swap via the Universal Router
        if (requireETHValue) {
            require(msg.value == amountIn, "Incorrect ETH amount provided");
            // Pass ETH value if swapping native ETH
            ROUTER.execute{value: amountIn}(commands, inputs, deadline);
        } else {
            require(msg.value == 0, "ETH not required for this swap");
            // Execute without ETH value if swapping ERC20 tokens
            // Assumes necessary approvals (e.g., via Permit2) are already in place
            ROUTER.execute(commands, inputs, deadline);
        }

        // Verify the amount of output tokens received
        if (outputTokenAddress == address(0)) {
            // If the output is native ETH, calculate the *change* in balance
            amountOut = address(this).balance - balanceBefore;
            (bool success, ) = msg.sender.call{value: amountOut}("");
            require(success, "ETH transfer failed");
        } else {
            // If the output is an ERC20 token, check the contract's token balance
            amountOut = IERC20(outputTokenAddress).balanceOf(address(this));
            require(IERC20(outputTokenAddress).transfer(msg.sender, amountOut), "Token transfer failed");
        }

        // Ensure the received amount meets the minimum requirement
        require(amountOut >= minAmountOut, "Insufficient output amount");

        // Return the actual amount of output tokens received
        return amountOut;
    }
}
