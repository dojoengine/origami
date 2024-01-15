// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@create3-factory/CREATE3Factory.sol";

import "../src/StarknetMessagingLocal.sol";
import "../src/Token.sol";
import "../src/L1DojoBridge.sol";
import "./BaseScript.sol";

bytes32 constant CREATE3_SALT = keccak256(bytes("CREATE3Salt"));

bytes32 constant SN_SALT = keccak256(bytes("SNSalt"));
bytes32 constant TOKEN_SALT = keccak256(bytes("TokenSalt"));
bytes32 constant BRIDGE_SALT = keccak256(bytes("BridgeSalt"));


/**
   Deploys the ContractMsg and StarknetMessagingLocal contracts.
   Very handy to quickly setup Anvil to debug.
*/
contract Deploy is BaseScript {
    function setUp() public {}

    function run() public {
        CREATE3Factory factory = CREATE3Factory(
            this.getEnv().CREATE3_FACTORY_ADDRESS
        );

        string memory json = "";

        vm.startBroadcast(this.getEnv().ACCOUNT_PRIVATE_KEY);

        address starknetAddress;
        if (this.isLocal()) {
            starknetAddress = address(new StarknetMessagingLocal());
        } else {
            starknetAddress = this.getEnv().STARKNET_ADDRESS;
        }
        vm.serializeString(
            json,
            "StarknetAddress",
            vm.toString(starknetAddress)
        );

        address tokenAddress;

        if (this.isLocal() /*|| this.isGoerli()*/) {
            tokenAddress = address(new Token());
        } else {
            tokenAddress = this.getEnv().TOKEN_ADDRESS;
        }
        vm.serializeString(json, "Token", vm.toString(tokenAddress));

        address l1DojoBridge = factory.deploy(
            BRIDGE_SALT,
            abi.encodePacked(
                type(L1DojoBridge).creationCode,
                abi.encode(
                    starknetAddress,
                    tokenAddress,
                    this.getEnv().L2_BRIDGE_ADDRESS
                )
            )
        );
        vm.serializeString(json, "L1DojoBridge", vm.toString(l1DojoBridge));

        vm.stopBroadcast();

        string memory data = vm.serializeBool(json, "success", true);

        string memory localLogs = "./logs/";
        vm.createDir(localLogs, true);
        vm.writeJson(
            data,
            string.concat(localLogs, this.getEnv().ENV, ".json")
        );
    }
}

contract GetBridgeAddress is BaseScript {
    function setUp() public {}

    function run() public returns (address bridgeAddress) {
        CREATE3Factory factory = CREATE3Factory(
            this.getEnv().CREATE3_FACTORY_ADDRESS
        );

        vm.startBroadcast(this.getEnv().ACCOUNT_PRIVATE_KEY);

        bridgeAddress = factory.getDeployed(
            this.getEnv().ACCOUNT_ADDRESS,
            BRIDGE_SALT
        );

        vm.stopBroadcast();
    }
}

contract Create3 is BaseScript {
    function setUp() public {}

    function run() public returns (address) {
        if (this.isLocal()) {
            vm.startBroadcast(this.getEnv().ACCOUNT_PRIVATE_KEY);
            CREATE3Factory factory = new CREATE3Factory();
            return address(factory);
        } else {
            console.log(
                "Already deployed on",
                this.getEnv().ENV,
                "at",
                this.getEnv().CREATE3_FACTORY_ADDRESS
            );
            return address(this.getEnv().CREATE3_FACTORY_ADDRESS);
        }
    }
}
