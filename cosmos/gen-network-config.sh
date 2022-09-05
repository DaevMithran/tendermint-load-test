#!/bin/bash

# Generates network config for an arbitrary amount of validators

set -euo pipefail

# sed in macos requires extra argument
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    SED_EXT=''
elif [[ "$OSTYPE" == "darwin"* ]]; then
    SED_EXT='.orig'
fi

# Params 
CHAIN_ID="simapp"

VALIDATORS_COUNT=4
SEEDS_COUNT=1
OBSERVER_COUNT=200

# global variables
NETWORK_CONFIG_DIR="network-config"

TMP_NODE_NAME="tmp"
TMP_NODE_HOME="${NETWORK_CONFIG_DIR}/${TMP_NODE_NAME}"
GENESIS_TMP="${TMP_NODE_HOME}/config/genesis.json"

export PATH="$PATH:../build/"

function init_node () {
    simd keys add $NODE_NAME --keyring-backend "test" --home "$NODE_HOME" &> "tmp_$NODE_NAME.txt"
    
    cat "tmp_$NODE_NAME.txt" | grep address | cut -d ':' -f 2 | xargs | tr -d "\n" > "keys/${NODE_NAME}_ADDRESS.txt"
    cat "tmp_$NODE_NAME.txt" | tail -1 | tr -d "\n" > "keys/${NODE_NAME}_MNEMONIC.txt"
    rm "tmp_$NODE_NAME.txt"

    simd add-genesis-account $NODE_NAME 20000000000stake --keyring-backend "test" --home "$NODE_HOME"
}

function init_validator () {
    NODE_HOME=$1
    NODE_NAME=$2

    echo "$NODE_NAME Initializing"

    simd init $NODE_NAME --home $NODE_HOME --chain-id $CHAIN_ID 2> /dev/null
    simd tendermint show-node-id --home $NODE_HOME > "${NODE_HOME}/node_id.txt"
    simd tendermint show-validator --home $NODE_HOME > "${NODE_HOME}/node_val_pubkey.txt"
}

function configure_validator () {
    NODE_HOME=$1
    NODE_NAME=$2
    
    echo "[${NODE_NAME}] Configuring app.toml and config.toml"

    APP_TOML="${NODE_HOME}/config/app.toml"
    CONFIG_TOML="${NODE_HOME}/config/config.toml"

    # sed -i $SED_EXT 's/minimum-gas-prices = ""/minimum-gas-prices = "25stake"/g' $APP_TOML
    sed -i $SED_EXT 's/enable = false/enable = true/g' $APP_TOML

    sed -i $SED_EXT 's|laddr = "tcp://127.0.0.1:26657"|laddr = "tcp://0.0.0.0:26657"|g' $CONFIG_TOML
    sed -i $SED_EXT 's|addr_book_strict = true|addr_book_strict = false|g' $CONFIG_TOML  
    sed -i $SED_EXT 's/timeout_propose = "3s"/timeout_propose = "1s"/g' $CONFIG_TOML
    # sed -i $SED_EXT 's/timeout_prevote = "1s"/timeout_prevote = "500ms"/g' $CONFIG_TOML
    # sed -i $SED_EXT 's/timeout_precommit = "1s"/timeout_precommit = "500ms"/g' $CONFIG_TOML
    sed -i $SED_EXT 's/timeout_commit = "5s"/timeout_commit = "1s"/g' $CONFIG_TOML
    sed -i $SED_EXT 's/create_empty_blocks = true/create_empty_blocks = false/g' $CONFIG_TOML
    sed -i $SED_EXT 's/create_empty_blocks_interval = "0s"/create_empty_blocks_interval = "60s"/g' $CONFIG_TOML
    sed -i $SED_EXT 's/flush_throttle_timeout = "100ms"/flush_throttle_timeout = "10ms"/g' $CONFIG_TOML
}

rm -rf $NETWORK_CONFIG_DIR
mkdir -m 777 $NETWORK_CONFIG_DIR
rm -rf keys
mkdir -m 777 keys
rm -rf $TMP_NODE_NAME
mkdir $TMP_NODE_HOME
mkdir "$TMP_NODE_HOME/config"
mkdir "$TMP_NODE_HOME/config/gentx"

# Generate validators
for ((i=0;i<VALIDATORS_COUNT;i++))
do 
    NODE_NAME="validator-$i"
    NODE_HOME="${NETWORK_CONFIG_DIR}/$NODE_NAME"

    init_validator $NODE_HOME $NODE_NAME
    configure_validator $NODE_HOME $NODE_NAME
done

for((i=0;i<SEEDS_COUNT;i++))
do 
    NODE_NAME="seed-$i"
    NODE_HOME="${NETWORK_CONFIG_DIR}/${NODE_NAME}"
    init_validator $NODE_HOME $NODE_NAME
    configure_validator $NODE_HOME $NODE_NAME
done

# num_procs=2
# num_jobs="\j"
for((i=0;i<OBSERVER_COUNT;i++))
do
    # while((${num_jobs@P} >= num_procs)); do
    #     wait -n
    # done
    NODE_NAME="node-$i"
    NODE_HOME="${NETWORK_CONFIG_DIR}/validator-0"
    init_node
done

echo "Adding genesis validators"
for ((i=0;i<VALIDATORS_COUNT;i++))
do 
    NODE_NAME="validator-$i"
    NODE_HOME="${NETWORK_CONFIG_DIR}/$NODE_NAME"
    GENESIS="${NODE_HOME}/config/genesis.json"

    if ((i==0))
    then 
        cp $GENESIS $GENESIS_TMP
    else
        cp $GENESIS_TMP $GENESIS
    fi

    simd keys add $NODE_NAME --keyring-backend "test" --home "${NODE_HOME}"

    simd add-genesis-account $NODE_NAME 20000000000000000stake --keyring-backend "test" --home "${NODE_HOME}"

    NODE_ID=$(simd tendermint show-node-id --home "${NODE_HOME}")
    NODE_VAL_PUBKEY=$(simd tendermint show-validator --home "${NODE_HOME}")
    simd gentx $NODE_NAME 1000000000000000stake --chain-id "${CHAIN_ID}" --node-id "${NODE_ID}" \
    --pubkey "${NODE_VAL_PUBKEY}" --keyring-backend "test"  --home "${NODE_HOME}"

    cp "${NODE_HOME}/config/genesis.json" $GENESIS_TMP
    cp -R "${NODE_HOME}/config/gentx/." "${TMP_NODE_HOME}/config/gentx"
done

echo "Collecting gentxs"
simd collect-gentxs --home $TMP_NODE_HOME
simd validate-genesis --home $TMP_NODE_HOME

# Distribute genesis
for ((i=0;i<VALIDATORS_COUNT;i++))
do 
    NODE_NAME="validator-$i"
    NODE_HOME="${NETWORK_CONFIG_DIR}/$NODE_NAME"
    cp $GENESIS_TMP "$NODE_HOME/config/genesis.json"
done

for ((i=0 ; i<SEEDS_COUNT ; i++))
do
  NODE_NAME="seed-$i"
  NODE_HOME="${NETWORK_CONFIG_DIR}/${NODE_NAME}"

  cp $GENESIS_TMP "${NODE_HOME}/config/genesis.json"
done

# Create seed node
for((i=0;i<SEEDS_COUNT;i++))
do 
    NODE_NAME="seed-$i"
    NODE_HOME="${NETWORK_CONFIG_DIR}/${NODE_NAME}"
    cp $GENESIS_TMP "${NODE_HOME}/config/genesis.json"
done

# Generate seeds.txt
SEEDS_STR=""
for((i=0;i<SEEDS_COUNT;i++))
do
    NODE_NAME="seed-$i"
    NODE_P2P_PORT="26656"
    NODE_HOME="${NETWORK_CONFIG_DIR}/${NODE_NAME}"

    if((i!=0))
    then
    SEEDS_STR="${SEEDS_STR},"
    fi

  SEEDS_STR="${SEEDS_STR}$(cat "${NODE_HOME}/node_id.txt")@${NODE_NAME}:${NODE_P2P_PORT}"
done


# distribute seeds
for ((i=0;i<VALIDATORS_COUNT;i++))
do 
    NODE_NAME="validator-$i"
    NODE_HOME="${NETWORK_CONFIG_DIR}/$NODE_NAME"
    CONFIG_TOML="${NODE_HOME}/config/config.toml"
    sed -i $SED_EXT 's/seeds = ""/seeds = "'"$SEEDS_STR"'"/g' $CONFIG_TOML
    sed -i $SED_EXT 's/persistent_peers = ""/persistent_peers = "'"$SEEDS_STR"'"/g' $CONFIG_TOML
done

echo "${SEEDS_STR}" > "${NETWORK_CONFIG_DIR}/seeds.txt"
rm -rf $TMP_NODE_HOME
