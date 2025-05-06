// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SuperDCASwap} from "../src/SuperDCASwap.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {console} from "forge-std/console.sol";

contract SuperDCASwapUnichainTest is Test {
    address constant UNIVERSAL_ROUTER_ADDRESS = 0xf70536B3bcC1bD1a972dc186A2cf84cC6da6Be5D;
    address constant POOL_MANAGER_ADDRESS = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    address constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address constant USDC_ADDRESS = 0x31d0220469e10c4E71834a79b1f276d740d3768F;
    address constant DCA_ADDRESS = 0xdCA0423d8a8b0e6c9d7756C16Ed73f36f1BadF54;
    address constant ETH = address(0);
    address constant GAUGE_ADDRESS = 0xEC67C9D1145aBb0FBBc791B657125718381DBa80;

    IERC20 USDC = IERC20(USDC_ADDRESS);
    IERC20 DCA = IERC20(DCA_ADDRESS);
    SuperDCASwap swapContract;

    PoolKey DCA_USDC_KEY = PoolKey({
        currency1: Currency.wrap(DCA_ADDRESS),
        currency0: Currency.wrap(USDC_ADDRESS),
        fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
        tickSpacing: 60,
        hooks: IHooks(GAUGE_ADDRESS)
    });

    PoolKey ETH_USDC_KEY = PoolKey({
        currency0: Currency.wrap(ETH),
        currency1: Currency.wrap(USDC_ADDRESS),
        fee: 3000,
        tickSpacing: 60,
        hooks: IHooks(address(0))
    });

    PoolKey DCA_ETH_KEY = PoolKey({
        currency0: Currency.wrap(ETH),
        currency1: Currency.wrap(DCA_ADDRESS),
        fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
        tickSpacing: 60,
        hooks: IHooks(GAUGE_ADDRESS)
    });

    function setUp() public {
        vm.selectFork(vm.createFork(vm.envString("UNICHAIN_RPC_URL")));

        swapContract = new SuperDCASwap(UNIVERSAL_ROUTER_ADDRESS, POOL_MANAGER_ADDRESS, PERMIT2_ADDRESS);

        vm.label(UNIVERSAL_ROUTER_ADDRESS, "UNIVERSAL_ROUTER");
        vm.label(POOL_MANAGER_ADDRESS, "POOL_MANAGER");
        vm.label(PERMIT2_ADDRESS, "PERMIT2");
        vm.label(USDC_ADDRESS, "USDC");
        vm.label(DCA_ADDRESS, "DCA");
    }

    function test_Swap_USDC_For_ETH_Multihop() public {
        uint128 amountIn = 1e6; // 1 USDC
        uint128 minAmountOut = 0; // Expecting some ETH out

        // Define the swap path: USDC -> DCA -> ETH
        PathKey[] memory path = new PathKey[](2);

        // Step 1: USDC -> DCA
        // Input: USDC (currency1), Output: DCA (currency0)
        // Pool: DCA/USDC (currency0 = DCA, currency1 = USDC)
        path[0] = PathKey({
            intermediateCurrency: Currency.wrap(DCA_ADDRESS), // Swapping USDC *for* DCA
            fee: DCA_USDC_KEY.fee,
            tickSpacing: DCA_USDC_KEY.tickSpacing,
            hooks: DCA_USDC_KEY.hooks,
            hookData: bytes("")
        });

        // Step 2: DCA -> ETH
        // Input: DCA (currency1), Output: ETH (currency0)
        // Pool: DCA/ETH (currency0 = ETH, currency1 = DCA)
        path[1] = PathKey({
            intermediateCurrency: Currency.wrap(ETH), // Swapping DCA *for* ETH
            fee: DCA_ETH_KEY.fee,
            tickSpacing: DCA_ETH_KEY.tickSpacing,
            hooks: DCA_ETH_KEY.hooks,
            hookData: bytes("")
        });

        // Define input currency
        Currency currencyIn = Currency.wrap(USDC_ADDRESS);

        // Fund this contract with USDC and transfer to swap contract
        deal(USDC_ADDRESS, address(this), amountIn);
        USDC.transfer(address(swapContract), amountIn);

        // Record initial ETH balance of caller and contract DCA balance
        uint256 initialETHBalance = address(this).balance;
        uint256 initialDCABalanceContract = DCA.balanceOf(address(swapContract));

        // Approve USDC spending via Permit2
        swapContract.approveTokenWithPermit2(USDC_ADDRESS, amountIn, uint48(block.timestamp + 1));

        // Execute the multi-hop swap
        uint256 amountOut = swapContract.swapExactInput(currencyIn, path, amountIn, minAmountOut);

        console.log("--- USDC -> ETH Multi-hop Swap ---");
        console.log("USDC In (raw, 6 decimals):", amountIn);
        console.log("USDC In (decimal):", amountIn / 1e6);
        console.log("ETH Out (wei):", amountOut);
        console.log("ETH Out (decimal, truncated):", amountOut / 1e18);

        // Calculate and log exchange rate (ETH wei per 1 USDC)
        if (amountIn > 0) {
            uint256 rateWeiPerUSDC = (amountOut * 1e6) / amountIn; // ETH wei received per 1 USDC (raw)
            console.log("Effective Rate (ETH wei per 1 USDC):", rateWeiPerUSDC);
            // Calculate the inverse rate: USDC per 1 ETH
            if (amountOut > 0) {
                uint256 rateUSDCperETH = (amountIn * 1e18) / amountOut / 1e6; // USDC (decimal) per 1 ETH (wei)
                console.log("Effective Rate (USDC per 1 ETH):", rateUSDCperETH);
            }
        } else {
            console.log("Cannot calculate rate: amountIn is zero.");
        }
        console.log("----------------------------------");

        // Verify swap results
        assertGt(amountOut, minAmountOut, "Swap failed: insufficient ETH output amount");
        assertEq(USDC.balanceOf(address(swapContract)), 0, "USDC not fully spent");
        assertEq(DCA.balanceOf(address(swapContract)), initialDCABalanceContract, "DCA balance changed unexpectedly"); // DCA is intermediate
        assertEq(address(this).balance - initialETHBalance, amountOut, "ETH not transferred to caller correctly");
    }

    function test_Swap_ETH_For_USDC_Multihop() public {
        uint128 amountIn = 0.00001 ether; // 1 ETH
        uint128 minAmountOut = 0; // Expecting some USDC out

        // Define the swap path: ETH -> DCA -> USDC
        PathKey[] memory path = new PathKey[](2);

        // Step 1: ETH -> DCA
        // Pool: DCA/ETH (currency0 = ETH, currency1 = DCA)
        // We are swapping currency0 for currency1. Intermediate output is DCA.
        path[0] = PathKey({
            intermediateCurrency: Currency.wrap(DCA_ADDRESS), // Swapping ETH *for* DCA
            fee: DCA_ETH_KEY.fee,
            tickSpacing: DCA_ETH_KEY.tickSpacing,
            hooks: DCA_ETH_KEY.hooks,
            hookData: bytes("")
        });

        // Step 2: DCA -> USDC
        // Pool: DCA/USDC (currency0 = USDC, currency1 = DCA)
        // We are swapping currency1 for currency0. Final output is USDC.
        path[1] = PathKey({
            intermediateCurrency: Currency.wrap(USDC_ADDRESS), // Swapping DCA *for* USDC
            fee: DCA_USDC_KEY.fee,
            tickSpacing: DCA_USDC_KEY.tickSpacing,
            hooks: DCA_USDC_KEY.hooks,
            hookData: bytes("")
        });

        // Define input currency
        Currency currencyIn = Currency.wrap(ETH);

        // Fund this contract with ETH
        vm.deal(address(this), amountIn);

        // Record initial balances of caller
        uint256 initialETHBalance = address(this).balance; // Should be amountIn
        uint256 initialUSDCBalance = USDC.balanceOf(address(this));
        uint256 initialDCABalance = DCA.balanceOf(address(swapContract));

        // Execute the multi-hop swap, sending ETH value
        uint256 amountOut = swapContract.swapExactInput{value: amountIn}(currencyIn, path, amountIn, minAmountOut);

        console.log("--- ETH -> USDC Multi-hop Swap ---");
        console.log("ETH In (wei):", amountIn);
        console.log("ETH In (decimal, truncated):", amountIn / 1e18);
        console.log("USDC Out (raw, 6 decimals):", amountOut);
        console.log("USDC Out (decimal):", amountOut / 1e6);

        // Calculate and log exchange rate (USDC per 1 ETH)
        if (amountIn > 0) {
            // Rate = (USDC amount * 10^18 / ETH amount) / 10^6 (to adjust for USDC decimals)
            uint256 rateUSDCperETH = (amountOut * 1e18) / amountIn / 1e6; // USDC (decimal) per 1 ETH (wei)
            console.log("Effective Rate (USDC per 1 ETH):", rateUSDCperETH);
            // Calculate the inverse rate: ETH wei per 1 USDC
            if (amountOut > 0) {
                uint256 rateWeiPerUSDC = (amountIn * 1e6) / amountOut; // ETH wei per 1 USDC (raw)
                console.log("Effective Rate (ETH wei per 1 USDC):", rateWeiPerUSDC);
            }
        } else {
            console.log("Cannot calculate rate: amountIn is zero.");
        }
        console.log("----------------------------------");

        // Verify swap results
        assertGt(amountOut, minAmountOut, "Swap failed: insufficient USDC output amount");
        assertEq(initialETHBalance - address(this).balance, amountIn, "ETH not fully spent");
        assertEq(DCA.balanceOf(address(swapContract)), initialDCABalance, "DCA balance changed unexpectedly"); // DCA is intermediate
        assertEq(USDC.balanceOf(address(this)) - initialUSDCBalance, amountOut, "USDC not transferred correctly");
    }

    receive() external payable {}
}
