#!/bin/bash
set -euo pipefail
pushd $(dirname "$0")/..

sleep 1

# export TX_SLEEP=200 # goerli ...
export TX_SLEEP=1
export WORLD_ADDRESS=$(cat ./target/dev/manifest.json | jq -r '.world.address')

export DOJO_TOKEN_ADDRESS=$(cat ./target/dev/manifest.json | jq -r '.contracts[] | select(.name == "dojo_bridge::dojo_token::dojo_token" ).address')
export DOJO_BRIDGE_ADDRESS=$(cat ./target/dev/manifest.json | jq -r '.contracts[] | select(.name == "dojo_bridge::dojo_bridge::dojo_bridge" ).address')

export CAIRO_DOJO_TOKEN_NAME=$(starkli to-cairo-string $DOJO_TOKEN_NAME)
export CAIRO_DOJO_TOKEN_SYMBOL=$(starkli to-cairo-string $DOJO_TOKEN_SYMBOL)

echo "---------------------------------------------------------------------------"
echo rpc : $RPC_URL
echo world : $WORLD_ADDRESS
echo "---------------------------------------------------------------------------"
echo token : $DOJO_TOKEN_ADDRESS
echo bridge: $DOJO_BRIDGE_ADDRESS
echo "---------------------------------------------------------------------------"
echo L1_BRIDGE_ADDRESS : $L1_BRIDGE_ADDRESS
echo DOJO_TOKEN_NAME   : $DOJO_TOKEN_NAME $CAIRO_DOJO_TOKEN_NAME 
echo DOJO_TOKEN_SYMBOL : $DOJO_TOKEN_SYMBOL $CAIRO_DOJO_TOKEN_SYMBOL
echo "---------------------------------------------------------------------------"
echo ACCOUNT_ADDRESS   : $ACCOUNT_ADDRESS
echo SOZO_PARAMS       : $SOZO_PARAMS
echo "---------------------------------------------------------------------------"


sleep 5

# enable system -> component authorizations 
DOJO_TOKEN_COMPONENTS=( "ERC20MetadataModel" "ERC20BalanceModel" "ERC20AllowanceModel" "ERC20BridgeableModel" )
DOJO_BRIDGE_COMPONENTS=("DojoBridgeModel")


for component in ${DOJO_TOKEN_COMPONENTS[@]}; do
    sozo auth writer $component $DOJO_TOKEN_ADDRESS --world $WORLD_ADDRESS $SOZO_PARAMS 
    sleep $TX_SLEEP
done

for component in ${DOJO_BRIDGE_COMPONENTS[@]}; do
    sozo auth writer $component $DOJO_BRIDGE_ADDRESS --world $WORLD_ADDRESS $SOZO_PARAMS 
    sleep $TX_SLEEP
done

printf "Default authorizations have been successfully set.\n"
sleep 2
echo "Initialization..."


# dojo_token
# fn initializer(ref self: ContractState, name: felt252, symbol: felt252, l2_bridge_address: ContractAddress)
echo "Initialize token"
sozo execute $DOJO_TOKEN_ADDRESS initializer -c $CAIRO_DOJO_TOKEN_NAME,$CAIRO_DOJO_TOKEN_SYMBOL,$DOJO_BRIDGE_ADDRESS $SOZO_PARAMS
sleep $TX_SLEEP

# dojo_bridge
# fn initializer(ref self: ContractState, l1_bridge: felt252, l2_token: ContractAddress)
echo "Initialize bridge"
sozo execute $DOJO_BRIDGE_ADDRESS initializer -c $L1_BRIDGE_ADDRESS,$DOJO_TOKEN_ADDRESS $SOZO_PARAMS
sleep $TX_SLEEP


