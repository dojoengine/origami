in /l1 & /sn Makefile, import the right .env
use `make` without argument to check current env vars

## L1 

- set STARKNET_ADDRESS (for goerli & mainnet)
- set TOKEN_ADDRESS (for mainnet)
- Pre-compute L1DojoBridge address with create3 

## Starknet

- set L1_BRIDGE_ADDRESS in sn/ .env
- Deploy contracts
- Set auth
- Initialize contracts

## L1

- set L2_BRIDGE_ADDRESS in l1/ .env
- Deploy L1DojoBridge



## Constructor / initiliazers

### L1
L1DojoBridge constructor :

`constructor(address _starknet, address _l1Token, uint256 _l2Bridge)`

### SN

dojo_bridge initializer :

`fn initializer(ref self: ContractState, l1_bridge: felt252, l2_token: ContractAddress)`

dojo_token initializer :

`fn initializer(ref self: ContractState, name: felt252, symbol: felt252, l2_bridge_address: ContractAddress)`


