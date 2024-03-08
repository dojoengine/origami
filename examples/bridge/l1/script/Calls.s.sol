// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "../src/StarknetMessagingLocal.sol";
import "../src/Token.sol";
import "../src/L1DojoBridge.sol";

import "./BaseScript.sol";


contract Deposit is BaseScript {
    address _token;
    address _L1DojoBridge;

    function setUp() public {
        string memory json = vm.readFile('./logs/local.json');

        _token = abi.decode(vm.parseJson(json,'.Token'), (address));
        _L1DojoBridge = abi.decode(vm.parseJson(json,'.L1DojoBridge'), (address));
    }

    function run() public{
        vm.startBroadcast(this.getEnv().ACCOUNT_PRIVATE_KEY);

        uint256 amount = 1_000 * 10**18;
        uint256 l2Recipient = 0x517ececd29116499f4a1b64b094da79ba08dfd54a3edaa316134c41f8160973;
        uint fee = 30_000;

        // mint token to owner
        Token(_token).mint(this.getEnv().ACCOUNT_ADDRESS, amount);
        
        // owner approve bridge for amount
        Token(_token).approve(_L1DojoBridge, amount);

        // call token bridge 
        L1DojoBridge(_L1DojoBridge).deposit{value: fee}(amount, l2Recipient, fee);

        vm.stopBroadcast();
    }
}


contract Withdraw is BaseScript {
    address _token;
    address _L1DojoBridge;

    function setUp() public {
        string memory json = vm.readFile('./logs/local.json');

        _token = abi.decode(vm.parseJson(json,'.Token'), (address));
        _L1DojoBridge = abi.decode(vm.parseJson(json,'.L1DojoBridge'), (address));
    }

    function run() public returns(uint256 balance){
        vm.startBroadcast(this.getEnv().ACCOUNT_PRIVATE_KEY);

        uint256 amount = 1_000 * 10**18;
        address l1Recipient = this.getEnv().ACCOUNT_ADDRESS;
        uint256 l2TxHash = 0;


        // call token bridge 
        L1DojoBridge(_L1DojoBridge).withdraw(amount, l1Recipient, l2TxHash);

        // get balance
        balance = Token(_token).balanceOf(l1Recipient);

        vm.stopBroadcast();
    }
}

contract GetBalance is BaseScript {
    address _token;

    function setUp() public {
        string memory json = vm.readFile('./logs/local.json');
        _token = abi.decode(vm.parseJson(json,'.Token'), (address));
    }

    function run() public returns(uint256 balance){
        vm.startBroadcast(this.getEnv().ACCOUNT_PRIVATE_KEY);

        // get balance
        balance = Token(_token).balanceOf(this.getEnv().ACCOUNT_ADDRESS);

        vm.stopBroadcast();
    }
}



contract MintToken is BaseScript {
    address _token;

    function setUp() public {
        string memory json = vm.readFile('./logs/local.json');
        _token = abi.decode(vm.parseJson(json,'.Token'), (address));
    }

    function run() public{
        vm.startBroadcast(this.getEnv().ACCOUNT_PRIVATE_KEY);

        uint256 amount = 1_000 * 10**18;
        // mint token to owner
        Token(_token).mint(this.getEnv().ACCOUNT_ADDRESS, amount);
        
        vm.stopBroadcast();
    }
}
