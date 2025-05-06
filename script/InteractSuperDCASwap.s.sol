// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {SuperDCASwap} from "../src/SuperDCASwap.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";

contract InteractSuperDCASwap is Script {
    // --- Configuration ---
    address constant USDC_ADDRESS = 0x31d0220469e10c4E71834a79b1f276d740d3768F;
    address constant DCA_ADDRESS = 0xdCA0423d8a8b0e6c9d7756C16Ed73f36f1BadF54;
    address constant ETH_ADDRESS = address(0);
    address constant GAUGE_ADDRESS = 0xEC67C9D1145aBb0FBBc791B657125718381DBa80;
    address constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    IERC20 USDC = IERC20(USDC_ADDRESS);
    SuperDCASwap swapContract;

    struct SwapMetrics {
        uint256 preSwapUSDC;
        uint256 preSwapDCA;
        uint256 preSwapETH;
        uint256 postSwapUSDC;
        uint256 postSwapDCA;
        uint256 postSwapETH;
        uint256 amountOut;
    }

    // Define Pool Keys (matching those in SuperDCASwapUnichain.t.sol)
    PoolKey DCA_USDC_KEY = PoolKey({
        currency1: Currency.wrap(DCA_ADDRESS),
        currency0: Currency.wrap(USDC_ADDRESS),
        fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
        tickSpacing: 60,
        hooks: IHooks(GAUGE_ADDRESS)
    });

    PoolKey DCA_ETH_KEY = PoolKey({
        currency0: Currency.wrap(ETH_ADDRESS),
        currency1: Currency.wrap(DCA_ADDRESS),
        fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
        tickSpacing: 60,
        hooks: IHooks(GAUGE_ADDRESS)
    });

    uint256 deployerPrivateKey;
    address deployerAddress;

    function setUp() public {
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        require(deployerPrivateKey != 0, "InteractScript: DEPLOYER_PRIVATE_KEY env var not set");
        deployerAddress = vm.addr(deployerPrivateKey);

        address payable swapContractAddress = payable(vm.envAddress("SUPERDCA_SWAP_ADDRESS"));
        require(swapContractAddress != address(0), "InteractScript: SUPERDCA_SWAP_ADDRESS env var not set");
        swapContract = SuperDCASwap(swapContractAddress);

        console.log("Using Deployer Address:", deployerAddress);
        console.log("Interacting with SuperDCASwap at:", swapContractAddress);
    }

    function logSwapResults(SwapMetrics memory metrics, bool isMultiHop) private view {
        if (isMultiHop) {
            console.log("\nMulti-hop Swap Results:");
            console.log("USDC spent:", metrics.preSwapUSDC - metrics.postSwapUSDC);
            console.log("DCA balance change:", metrics.postSwapDCA - metrics.preSwapDCA, "(should be 0 as it's intermediate)");
            console.log("ETH received:", metrics.postSwapETH - metrics.preSwapETH);
            console.log("ETH amount from swap:", metrics.amountOut);
        } else {
            console.log("\nSwap Results:");
            console.log("USDC spent:", metrics.preSwapUSDC - metrics.postSwapUSDC);
            console.log("DCA received:", metrics.postSwapDCA - metrics.preSwapDCA);
            console.log("DCA amount from swap:", metrics.amountOut);
        }
    }

    function recordPreSwapBalances() private view returns (SwapMetrics memory) {
        return SwapMetrics({
            preSwapUSDC: USDC.balanceOf(address(swapContract)),
            preSwapDCA: IERC20(DCA_ADDRESS).balanceOf(address(swapContract)),
            preSwapETH: address(swapContract).balance,
            postSwapUSDC: 0,
            postSwapDCA: 0,
            postSwapETH: 0,
            amountOut: 0
        });
    }

    function recordPostSwapBalances(SwapMetrics memory metrics) private view returns (SwapMetrics memory) {
        metrics.postSwapUSDC = USDC.balanceOf(address(swapContract));
        metrics.postSwapDCA = IERC20(DCA_ADDRESS).balanceOf(address(swapContract));
        metrics.postSwapETH = address(swapContract).balance;
        return metrics;
    }

    function run() external {
        uint128 usdcAmountForSingleSwap = 1e6; // 1 USDC
        uint128 usdcAmountForMultiSwap = 1e6; // 1 USDC
        uint128 totalUSDCNeeded = usdcAmountForSingleSwap + usdcAmountForMultiSwap;

        // --- Approvals ---
        vm.startBroadcast(deployerPrivateKey);

        // 1. Check if the deployer has USDC in their wallet
        console.log("Deployer has", USDC.balanceOf(deployerAddress), "USDC in their wallet");

        // 2. Approve USDC to Permit2 and then to the Router via Permit2
        USDC.approve(PERMIT2_ADDRESS, type(uint256).max);
        console.log("Approved Permit2 to spend USDC");

        swapContract.approveTokenWithPermit2(USDC_ADDRESS, uint160(totalUSDCNeeded), uint48(block.timestamp + 1 hours));
        console.log("Approved Router via Permit2 to spend", totalUSDCNeeded / 1e6, "USDC");

        // --- Swap 1: Single Hop (USDC -> DCA) ---
        console.log("\n--- Executing Single Swap: USDC -> DCA ---");
        bool zeroForOneSingle = true;

        // Send the tokens to transfer to the contract
        USDC.transfer(address(swapContract), usdcAmountForSingleSwap);
        console.log("Sent USDC to contract");

        // Record balances and execute swap
        SwapMetrics memory singleHopMetrics = recordPreSwapBalances();
        console.log("Pre-swap USDC balance in contract:", singleHopMetrics.preSwapUSDC);
        console.log("Pre-swap DCA balance in contract:", singleHopMetrics.preSwapDCA);

        singleHopMetrics.amountOut = swapContract.swapExactInputSingle(
            DCA_USDC_KEY,
            zeroForOneSingle,
            usdcAmountForSingleSwap,
            0 // minAmountOut
        );

        singleHopMetrics = recordPostSwapBalances(singleHopMetrics);
        logSwapResults(singleHopMetrics, false);

        // --- Swap 2: Multi Hop (USDC -> DCA -> ETH) ---
        console.log("\n--- Executing Multi Swap: USDC -> DCA -> ETH ---");
        PathKey[] memory path = new PathKey[](2);
        
        // Configure path for USDC -> DCA -> ETH
        path[0] = PathKey({
            intermediateCurrency: Currency.wrap(DCA_ADDRESS),
            fee: DCA_USDC_KEY.fee,
            tickSpacing: DCA_USDC_KEY.tickSpacing,
            hooks: DCA_USDC_KEY.hooks,
            hookData: bytes("")
        });
        path[1] = PathKey({
            intermediateCurrency: Currency.wrap(ETH_ADDRESS),
            fee: DCA_ETH_KEY.fee,
            tickSpacing: DCA_ETH_KEY.tickSpacing,
            hooks: DCA_ETH_KEY.hooks,
            hookData: bytes("")
        });

        // Send tokens and record pre-swap balances
        USDC.transfer(address(swapContract), usdcAmountForMultiSwap);
        console.log("Sent USDC to contract");

        SwapMetrics memory multiHopMetrics = recordPreSwapBalances();
        console.log("Pre-swap USDC balance in contract:", multiHopMetrics.preSwapUSDC);
        console.log("Pre-swap DCA balance in contract:", multiHopMetrics.preSwapDCA);
        console.log("Pre-swap ETH balance in contract:", multiHopMetrics.preSwapETH);

        multiHopMetrics.amountOut = swapContract.swapExactInput(
            Currency.wrap(USDC_ADDRESS),
            path,
            usdcAmountForMultiSwap,
            0 // minAmountOut
        );

        multiHopMetrics = recordPostSwapBalances(multiHopMetrics);
        logSwapResults(multiHopMetrics, true);

        // Check final balances
        console.log("\n--- Final Contract Balances ---");
        console.log("Final USDC in contract:", USDC.balanceOf(address(swapContract)));
        console.log("Final DCA in contract:", IERC20(DCA_ADDRESS).balanceOf(address(swapContract)));
        console.log("Final ETH in contract:", address(swapContract).balance);
        
        vm.stopBroadcast();
        console.log("\nInteraction script finished.");
    }
} 