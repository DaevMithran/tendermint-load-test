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

VALIDATORS_COUNT=16

# global variables
NETWORK_CONFIG_DIR="network-config"
TMP_VALIDATOR_HOME="${NETWORK_CONFIG_DIR}/tmp"
GENESIS_TMP="${NETWORK_CONFIG_DIR}/genesis.json"
GENESIS_TIME="2022-08-25T06:26:52.671073265Z"

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
    NODE_P2P_PORT="26656"
    VALIDATORS_STR=""

    echo "$NODE_NAME Configuring genesis"

    GENESIS="${NODE_HOME}/config/genesis.json"
    VALIDATORS=$(jq -c . "$TMP_VALIDATOR_HOME/validators.json" | jq .)
    CONFIG="${NODE_HOME}/config/config.toml"
    # set chain id
    jq '.validators='"$VALIDATORS"' | .chain_id="'"$CHAIN_ID"'" | .genesis_time="'"$GENESIS_TIME"'"' $GENESIS > $GENESIS_TMP
    cp $GENESIS_TMP $GENESIS
    sed -i $SED_EXT 's|laddr = "tcp://127.0.0.1:26657"|laddr = "tcp://0.0.0.0:26657"|g' $CONFIG
    sed -i $SED_EXT 's|addr_book_strict = true|addr_book_strict = false|g' $CONFIG

    for ((j=0;j<VALIDATORS_COUNT;j++))
    do
        VALIDATOR="validator-$j"
        VALIDATOR_HOME="${NETWORK_CONFIG_DIR}/$VALIDATOR"
        if [ $VALIDATOR != $NODE_NAME ]
        then
            VALIDATORS_STR="${VALIDATORS_STR}$(cat "${VALIDATOR_HOME}/node_id.txt")@${VALIDATOR}:${NODE_P2P_PORT},"
        fi
    done
    VALIDATORS_STR=${VALIDATORS_STR::-1}

    sed -i $SED_EXT 's|persistent_peers = ""|persistent_peers = "'"$VALIDATORS_STR"'"|g' $CONFIG
}

sudo rm -rf $NETWORK_CONFIG_DIR
mkdir -m 777 $NETWORK_CONFIG_DIR

rm -rf $TMP_VALIDATOR_HOME
mkdir -m 777 $TMP_VALIDATOR_HOME
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

echo $VALIDATORS_STR > "${NETWORK_CONFIG_DIR}/validators.txt"
