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

VALIDATORS_COUNT=1

# global variables
NETWORK_CONFIG_DIR="network-config"
TMP_VALIDATOR_HOME="${NETWORK_CONFIG_DIR}/tmp"


function init_node () {
    NODE_HOME=$1
    NODE_NAME=$2

    echo "$NODE_NAME Initializing"

    tendermint init --home $NODE_HOME 2> /dev/null
}

function configure_genesis() {
    NODE_HOME=$1
    NODE_NAME=$2
    
    echo "$NODE_NAME Configuring genesis"

    GENESIS="${NODE_HOME}/config/genesis.json"
    GENESIS_TMP="${NODE_HOME}/config/genesis_tmp.json"
    VALIDATORS=$(jq -c . "$TMP_VALIDATOR_HOME/validators.json" | jq .)
    # set chain id
    jq '.validators='"$VALIDATORS"' | .chain_id="'"$CHAIN_ID"'"' $GENESIS > $GENESIS_TMP
    mv $GENESIS_TMP $GENESIS
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





