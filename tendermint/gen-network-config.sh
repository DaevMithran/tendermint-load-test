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
CHAIN_ID="testTendermint"
TXN_TYPE="commit"

VALIDATORS_COUNT=4
SEEDS_COUNT=1

# global variables
NETWORK_CONFIG_DIR="network-config"
TMP_VALIDATOR_HOME="${NETWORK_CONFIG_DIR}/tmp"
GENESIS_TMP="${NETWORK_CONFIG_DIR}/genesis.json"

function init_node () {
    NODE_HOME=$1
    NODE_NAME=$2

    echo "$NODE_NAME Initializing"

    tendermint init --home $NODE_HOME 2> /dev/null
    tendermint show-node-id --home $NODE_HOME > "${NODE_HOME}/node_id.txt"
    tendermint show-validator --home $NODE_HOME > "${NODE_HOME}/node_val_pubkey.txt"
}

function configure_genesis() {
    NODE_HOME=$1
    NODE_NAME=$2
    
    echo "$NODE_NAME Configuring genesis"

    GENESIS="${NODE_HOME}/config/genesis.json"
    VALIDATORS=$(jq -c . "$TMP_VALIDATOR_HOME/validators.json" | jq .)
    CONFIG="${NODE_HOME}/config/config.toml"
    # set chain id
    jq '.validators='"$VALIDATORS"' | .chain_id="'"$CHAIN_ID"'"' $GENESIS > $GENESIS_TMP
    cp $GENESIS_TMP $GENESIS
    sed -i $SED_EXT 's|laddr = "tcp://127.0.0.1:26657"|laddr = "tcp://0.0.0.0:26657"|g' $CONFIG
    sed -i $SED_EXT 's|addr_book_strict = true|addr_book_strict = false|g' $CONFIG
    # sed -i $SED_EXT 's|enable = false|enable = true|g' $CONFIG
}

rm -rf $NETWORK_CONFIG_DIR
mkdir $NETWORK_CONFIG_DIR

rm -rf $TMP_VALIDATOR_HOME
mkdir $TMP_VALIDATOR_HOME
jq -n '[]' > "$TMP_VALIDATOR_HOME/validators.json"

# Adding genesis validators
for ((i=0;i<VALIDATORS_COUNT;i++))
do 
    NODE_NAME="validator-$i"
    NODE_HOME="${NETWORK_CONFIG_DIR}/$NODE_NAME"
    init_node $NODE_HOME $NODE_NAME
    VALIDATORS="${TMP_VALIDATOR_HOME}/validators.json"
    GENESIS="${NODE_HOME}/config/genesis.json"

    jv=$(jq -c . $VALIDATORS | jq .)
    jg=$(jq '.validators[]' $GENESIS | jq .)
    echo $jv | jq '. += ['"$jg"']' > "$VALIDATORS"
done

# Configure genesis
for ((i=0;i<VALIDATORS_COUNT;i++))
do 
    NODE_NAME="validator-$i"
    NODE_HOME="${NETWORK_CONFIG_DIR}/$NODE_NAME"
    configure_genesis $NODE_HOME $NODE_NAME
done

# Create seed node
for((i=0;i<SEEDS_COUNT;i++))
do 
    NODE_NAME="seed-$i"
    NODE_HOME="${NETWORK_CONFIG_DIR}/${NODE_NAME}"
    init_node $NODE_HOME $NODE_NAME
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

echo "${SEEDS_STR}" > "${NETWORK_CONFIG_DIR}/seeds.txt"
