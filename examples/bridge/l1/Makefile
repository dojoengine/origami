include .env.local

export

PARAMS := --broadcast --rpc-url ${ETH_RPC_URL} -v

all: 
	@echo "********************************************************************"
	@echo "ENV                     : ${ENV}"
	@echo "********************************************************************"
	@echo "ETH_RPC_URL             : ${ETH_RPC_URL}"
	@echo "ACCOUNT_ADDRESS         : ${ACCOUNT_ADDRESS}"
	@echo "CREATE3_FACTORY_ADDRESS : ${CREATE3_FACTORY_ADDRESS}"
	@echo "STARKNET_ADDRESS        : ${STARKNET_ADDRESS}"
	@echo "TOKEN_ADDRESSS          : ${TOKEN_ADDRESSS}"
	@echo "L2_BRIDGE_ADDRESS       : ${L2_BRIDGE_ADDRESS}"
	@echo "********************************************************************"

anvil:
	anvil --chain-id 1337

anvil_slow:
	anvil --chain-id 1337 --block-time 10

create3: 
	forge script ./script/Deploy.s.sol:Create3 ${PARAMS}

get_bridge_address: 
	forge script ./script/Deploy.s.sol:GetBridgeAddress ${PARAMS}

deploy: 
	forge script ./script/Deploy.s.sol:Deploy ${PARAMS}

deposit: 
	forge script ./script/Calls.s.sol:Deposit ${PARAMS}

withdraw: 
	forge script ./script/Calls.s.sol:Withdraw ${PARAMS}

get_balance: 
	forge script ./script/Calls.s.sol:GetBalance ${PARAMS}

mint_token: 
	forge script ./script/Calls.s.sol:MintToken ${PARAMS}