// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {AMMFactory} from "../src/core/AMMFactory.sol";
import {AMM} from "../src/core/AMM.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/console.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy AMMFactory implementation
        AMMFactory factoryImpl = new AMMFactory();
        
        // Initialize factory proxy
        bytes memory factoryInitData = abi.encodeWithSelector(
            AMMFactory.initialize.selector
        );
        
        // Deploy factory proxy
        ERC1967Proxy factoryProxy = new ERC1967Proxy(
            address(factoryImpl),
            factoryInitData
        );
        
        // Get factory instance for logging
        AMMFactory factory = AMMFactory(address(factoryProxy));
        
        // Log deployed addresses
        console.log("Factory Implementation:", address(factoryImpl));
        console.log("Factory Proxy:", address(factoryProxy));
        console.log("AMM Implementation:", factory.ammImplementation());

        vm.stopBroadcast();
    }
} 