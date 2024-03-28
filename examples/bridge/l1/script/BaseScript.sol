// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@create3-factory/CREATE3Factory.sol";

contract BaseScript is Script {
    struct Env {
        string ENV;
        string ETH_RPC_URL;
        uint256 ACCOUNT_PRIVATE_KEY;
        address ACCOUNT_ADDRESS;
        address CREATE3_FACTORY_ADDRESS;
        address STARKNET_ADDRESS;
        uint256 L2_BRIDGE_ADDRESS;
        address TOKEN_ADDRESS;
    }

    Env public env;

    constructor() {
        loadEnv();
    }

    function getEnv() public view returns (Env memory ) {
       return env;
    }

    function loadEnv() public {
        console.log("Loading Env...");

        env.ENV = vm.envString("ENV");
        env.ETH_RPC_URL = vm.envString("ETH_RPC_URL");
        env.ACCOUNT_PRIVATE_KEY = vm.envUint("ACCOUNT_PRIVATE_KEY");
        env.ACCOUNT_ADDRESS = vm.envAddress("ACCOUNT_ADDRESS");
        env.CREATE3_FACTORY_ADDRESS = vm.envAddress("CREATE3_FACTORY_ADDRESS");
        env.STARKNET_ADDRESS = vm.envAddress("STARKNET_ADDRESS");
        env.L2_BRIDGE_ADDRESS = vm.envUint("L2_BRIDGE_ADDRESS");
        env.TOKEN_ADDRESS = vm.envAddress("TOKEN_ADDRESS");

        console.log("ENV :", env.ENV);
        console.log("ETH_RPC_URL :", env.ETH_RPC_URL);

    }

    function isLocal() public view returns (bool) {
        return stringEquals(env.ENV, "local");
    }
    
    function isGoerli() public view returns (bool) {
        return stringEquals(env.ENV, "goerli");
    }

    function stringEquals(string memory a, string memory b) public pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}
