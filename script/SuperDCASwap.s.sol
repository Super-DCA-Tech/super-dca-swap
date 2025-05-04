// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {SuperDCASwap} from "../src/SuperDCASwap.sol";
import {console} from "forge-std/console.sol";

contract DeploySuperDCASwap is Script {
    address constant UNIVERSAL_ROUTER_ADDRESS = 0xf70536B3bcC1bD1a972dc186A2cf84cC6da6Be5D;
    address constant POOL_MANAGER_ADDRESS = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    address constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    uint256 deployerPrivateKey;

    function setUp() public virtual {
        deployerPrivateKey = vm.envOr(
            "DEPLOYER_PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
    }

    function run() external returns (SuperDCASwap) {
        console.log("Deploying SuperDCASwap with:");
        console.log("  Universal Router:", UNIVERSAL_ROUTER_ADDRESS);
        console.log("  Pool Manager:", POOL_MANAGER_ADDRESS);
        console.log("  Permit2:", PERMIT2_ADDRESS);

        vm.startBroadcast(deployerPrivateKey);

        SuperDCASwap swapContract = new SuperDCASwap(UNIVERSAL_ROUTER_ADDRESS, POOL_MANAGER_ADDRESS, PERMIT2_ADDRESS);

        vm.stopBroadcast();

        console.log("SuperDCASwap deployed at:", address(swapContract));
        return swapContract;
    }
}
