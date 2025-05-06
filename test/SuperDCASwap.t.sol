// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SuperDCASwap} from "../src/SuperDCASwap.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";

contract SuperDCASwapTest is Test {
    address constant UNIVERSAL_ROUTER_ADDRESS = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;
    address constant POOL_MANAGER_ADDRESS = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WBTC_ADDRESS = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant ETH = address(0);

    IERC20 USDC = IERC20(USDC_ADDRESS);
    IERC20 WBTC = IERC20(WBTC_ADDRESS);
    SuperDCASwap swapContract;

    PoolKey WBTC_USDC_KEY = PoolKey({
        currency0: Currency.wrap(WBTC_ADDRESS),
        currency1: Currency.wrap(USDC_ADDRESS),
        fee: 3000,
        tickSpacing: 60,
        hooks: IHooks(address(0))
    });

    PoolKey ETH_USDC_KEY = PoolKey({
        currency0: Currency.wrap(ETH),
        currency1: Currency.wrap(USDC_ADDRESS),
        fee: 3000,
        tickSpacing: 60,
        hooks: IHooks(address(0))
    });

    PoolKey WBTC_ETH_KEY = PoolKey({
        currency0: Currency.wrap(ETH),
        currency1: Currency.wrap(WBTC_ADDRESS),
        fee: 3000,
        tickSpacing: 60,
        hooks: IHooks(address(0))
    });

    function setUp() public {
        vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL")));

        swapContract = new SuperDCASwap(UNIVERSAL_ROUTER_ADDRESS, POOL_MANAGER_ADDRESS, PERMIT2_ADDRESS);

        vm.label(UNIVERSAL_ROUTER_ADDRESS, "UNIVERSAL_ROUTER");
        vm.label(POOL_MANAGER_ADDRESS, "POOL_MANAGER");
        vm.label(PERMIT2_ADDRESS, "PERMIT2");
        vm.label(USDC_ADDRESS, "USDC");
        vm.label(WBTC_ADDRESS, "WBTC");
    }

    function test_Swap_WBTC_For_USDC() public {
        uint128 amountIn = 1e7; // 0.1 WBTC
        uint128 minAmountOut = 0;

        // Fund the user (test contract) with WBTC and transfer to swap contract
        deal(WBTC_ADDRESS, address(this), amountIn);
        IERC20(WBTC_ADDRESS).transfer(address(swapContract), amountIn);

        // Approve tokens via Permit2 as swap contract
        vm.prank(address(swapContract));
        swapContract.approveTokenWithPermit2(WBTC_ADDRESS, amountIn, uint48(block.timestamp + 1));

        // Execute swap (WBTC -> USDC) expecting USDC to this contract
        uint256 amountOut = swapContract.swapExactInputSingle(
            WBTC_USDC_KEY,
            true, // zeroForOne
            amountIn,
            minAmountOut
        );

        // Verify swap results
        assertGt(amountOut, minAmountOut, "Swap failed: insufficient output amount");
        assertEq(WBTC.balanceOf(address(swapContract)), 0, "WBTC not fully spent");
        assertEq(USDC.balanceOf(address(swapContract)), 0, "Contract should not retain USDC");
        assertGt(USDC.balanceOf(address(this)), 0, "Caller did not receive USDC");
    }

    function test_Swap_ETH_For_USDC() public {
        uint128 amountIn = 1 ether; // 1 ETH
        uint128 minAmountOut = 0;

        // Fund this contract with ETH
        vm.deal(address(this), amountIn);

        // Execute swap (ETH -> USDC: zeroForOne = true)
        uint256 amountOut = swapContract.swapExactInputSingle{value: amountIn}(
            ETH_USDC_KEY,
            true, // zeroForOne
            amountIn,
            minAmountOut
        );

        // Verify swap results
        assertGt(amountOut, minAmountOut, "Swap failed: insufficient output amount");
        assertEq(address(swapContract).balance, 0, "ETH not fully spent");
        assertEq(USDC.balanceOf(address(swapContract)), 0, "Contract should not retain USDC");
        assertGt(USDC.balanceOf(address(this)), 0, "Caller did not receive USDC");
    }

    function test_Swap_USDC_For_ETH() public {
        uint128 amountIn = 1000e6; // 1000 USDC
        uint128 minAmountOut = 0;

        // Fund this contract with USDC and transfer to swap contract
        deal(USDC_ADDRESS, address(this), amountIn);
        USDC.transfer(address(swapContract), amountIn);

        // Record initial ETH balance of caller
        uint256 initialETHBalance = address(this).balance;

        // Approve tokens
        vm.prank(address(swapContract));
        swapContract.approveTokenWithPermit2(USDC_ADDRESS, amountIn, uint48(block.timestamp + 1));

        // Execute swap (USDC -> ETH: zeroForOne = false)
        uint256 amountOut = swapContract.swapExactInputSingle(
            ETH_USDC_KEY,
            false, // zeroForOne
            amountIn,
            minAmountOut
        );

        // Verify swap results
        assertGt(amountOut, minAmountOut, "Swap failed: insufficient output amount");
        assertEq(USDC.balanceOf(address(swapContract)), 0, "USDC not fully spent");
        assertEq(address(this).balance - initialETHBalance, amountOut, "ETH not transferred to caller correctly");
    }

    function test_Swap_USDC_For_ETH_Multihop() public {
        uint128 amountIn = 5000e6; // 5000 USDC
        uint128 minAmountOut = 0; // Expecting some ETH out

        // Define the swap path: USDC -> WBTC -> ETH
        PathKey[] memory path = new PathKey[](2);

        // Step 1: USDC -> WBTC
        // Input: USDC (currency1), Output: WBTC (currency0)
        // Pool: WBTC/USDC (currency0 = WBTC, currency1 = USDC)
        path[0] = PathKey({
            intermediateCurrency: Currency.wrap(WBTC_ADDRESS), // Swapping USDC *for* WBTC
            fee: WBTC_USDC_KEY.fee,
            tickSpacing: WBTC_USDC_KEY.tickSpacing,
            hooks: WBTC_USDC_KEY.hooks,
            hookData: bytes("")
        });

        // Step 2: WBTC -> ETH
        // Input: WBTC (currency1), Output: ETH (currency0)
        // Pool: WBTC/ETH (currency0 = ETH, currency1 = WBTC)
        path[1] = PathKey({
            intermediateCurrency: Currency.wrap(ETH), // Swapping WBTC *for* ETH
            fee: WBTC_ETH_KEY.fee,
            tickSpacing: WBTC_ETH_KEY.tickSpacing,
            hooks: WBTC_ETH_KEY.hooks,
            hookData: bytes("")
        });

        // Define input currency
        Currency currencyIn = Currency.wrap(USDC_ADDRESS);

        // Fund this contract with USDC and transfer to swap contract
        deal(USDC_ADDRESS, address(this), amountIn);
        USDC.transfer(address(swapContract), amountIn);

        // Record initial ETH balance of caller and contract WBTC balance
        uint256 initialETHBalance = address(this).balance;
        uint256 initialWBTCBalanceContract = WBTC.balanceOf(address(swapContract));

        // Approve USDC spending via Permit2
        vm.prank(address(swapContract));
        swapContract.approveTokenWithPermit2(USDC_ADDRESS, amountIn, uint48(block.timestamp + 1));

        // Execute the multi-hop swap
        uint256 amountOut = swapContract.swapExactInput(currencyIn, path, amountIn, minAmountOut);

        // Verify swap results
        assertGt(amountOut, minAmountOut, "Swap failed: insufficient ETH output amount");
        assertEq(USDC.balanceOf(address(swapContract)), 0, "USDC not fully spent");
        assertEq(WBTC.balanceOf(address(swapContract)), initialWBTCBalanceContract, "WBTC balance changed unexpectedly"); // WBTC is intermediate
        assertEq(address(this).balance - initialETHBalance, amountOut, "ETH not transferred to caller correctly");
    }

    receive() external payable {}
}
