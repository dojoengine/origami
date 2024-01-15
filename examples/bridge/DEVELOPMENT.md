For local use
Make sure both Makefiles use .env.local
You can just use `make` without argument to check current env vars

# ETH 

### Terminal 1

Launch anvil

```sh
cd l1
make anvil
```

### Terminal 2

Deploy create3 contract for deterministic contract address
```sh
cd l1
make create3
```

Deploy eth $TOKEN & L1DojoBridge
```sh
make deploy
```

# Starknet

### Terminal 1

Launch katana with messaging

```sh
cd sn
make katana_msg
# or
katana --messaging anvil.messaging.json
```

### Terminal 2

Migrate & initialize contracts
```sh
cd sn
make migrate_and_init
# or
make migrate
make initialize
```

Fund an address in ETH
```sh
./scripts/fund.sh 0x1234
```

# Bridging

## from ETH to Starknet

it mint tokens & approve bridge & call deposit on ETH bridge
```sh
make deposit
```

## from Starknet to ETH

get balance on Starknet
```sh
scarb run get_balance
```

withdraw from Starknet to ETH
```sh
scarb run withdraw
```

## after

withdraw tokens from ETH bridge
```sh
make withdraw
```

check token balance on ETH 
```sh
make get_balance
```