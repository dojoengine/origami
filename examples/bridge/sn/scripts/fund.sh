#!/bin/bash
set -euo pipefail
pushd $(dirname "$0")/..

sleep 1

export ADDR_TO_FUND=$1
export RPC_URL="http://localhost:5050"
export FEE_TOKEN_ADDRESS="0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"

starkli invoke --rpc $RPC_URL --account ./accounts/starkli_katana.json \
--private-key 0x1800000000300000180000000000030000000000003006001800006600 \
$FEE_TOKEN_ADDRESS transfer $ADDR_TO_FUND 1000000000000000000 0
