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
CHAIN_ID="checkers"

VALIDATORS_COUNT=4
SEEDS_COUNT=1

# global variables
NETWORK_CONFIG_DIR="network-config"

TMP_NODE_NAME="tmp"
TMP_NODE_HOME="${NETWORK_CONFIG_DIR}/${TMP_NODE_NAME}"
GENESIS_TMP="${TMP_NODE_HOME}/config/genesis.json"

function init_node () {
    NODE_HOME=$1
    NODE_NAME=$2

    echo "$NODE_NAME Initializing"

    checkersd init $NODE_NAME --home $NODE_HOME 2> /dev/null
    checkersd tendermint show-node-id --home $NODE_HOME > "${NODE_HOME}/node_id.txt"
    checkersd tendermint show-validator --home $NODE_HOME > "${NODE_HOME}/node_val_pubkey.txt"
}

function configure_node () {
    NODE_HOME=$1
    NODE_NAME=$2
    
    echo "[${NODE_NAME}] Configuring app.toml and config.toml"

    APP_TOML="${NODE_HOME}/config/app.toml"
    CONFIG_TOML="${NODE_HOME}/config/config.toml"

    sed -i $SED_EXT 's/minimum-gas-prices = ""/minimum-gas-prices = "25ntoken"/g' $APP_TOML
    sed -i $SED_EXT 's/enable = false/enable = true/g' $APP_TOML

    sed -i $SED_EXT 's|laddr = "tcp://127.0.0.1:26657"|laddr = "tcp://0.0.0.0:26657"|g' $CONFIG_TOML
    sed -i $SED_EXT 's|addr_book_strict = true|addr_book_strict = false|g' $CONFIG_TOML

    sed -i $SED_EXT 's/timeout_propose = "3s"/timeout_propose = "500ms"/g' $CONFIG_TOML
    sed -i $SED_EXT 's/timeout_prevote = "1s"/timeout_prevote = "500ms"/g' $CONFIG_TOML
    sed -i $SED_EXT 's/timeout_precommit = "1s"/timeout_precommit = "500ms"/g' $CONFIG_TOML
    sed -i $SED_EXT 's/timeout_commit = "5s"/timeout_commit = "500ms"/g' $CONFIG_TOML

}

rm -rf $NETWORK_CONFIG_DIR
mkdir $NETWORK_CONFIG_DIR

rm -rf $TMP_NODE_NAME
mkdir $TMP_NODE_HOME
mkdir "$TMP_NODE_HOME/config"
mkdir "$TMP_NODE_HOME/config/gentx"

# Generate validators
for ((i=0;i<VALIDATORS_COUNT;i++))
do 
    NODE_NAME="validator-$i"
    NODE_HOME="${NETWORK_CONFIG_DIR}/$NODE_NAME"

    init_node $NODE_HOME $NODE_NAME
    configure_node $NODE_HOME $NODE_NAME
done

for((i=0;i<SEEDS_COUNT;i++))
do 
    NODE_NAME="seed-$i"
    NODE_HOME="${NETWORK_CONFIG_DIR}/${NODE_NAME}"
    init_node $NODE_HOME $NODE_NAME
    configure_node $NODE_HOME $NODE_NAME
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

    checkersd keys add $NODE_NAME --keyring-backend "test" --home "${NODE_HOME}"
    checkersd add-genesis-account $NODE_NAME 20000000000000000stake --keyring-backend "test" --home "${NODE_HOME}"

    NODE_ID=$(checkersd tendermint show-node-id --home "${NODE_HOME}")
    NODE_VAL_PUBKEY=$(checkersd tendermint show-validator --home "${NODE_HOME}")
    checkersd gentx $NODE_NAME 1000000000000000stake --chain-id "${CHAIN_ID}" --node-id "${NODE_ID}" \
    --pubkey "${NODE_VAL_PUBKEY}" --keyring-backend "test"  --home "${NODE_HOME}"

    cp "${NODE_HOME}/config/genesis.json" $GENESIS_TMP
    cp -R "${NODE_HOME}/config/gentx/." "${TMP_NODE_HOME}/config/gentx"
done

echo "Collecting gentxs"
checkersd collect-gentxs --home $TMP_NODE_HOME
checkersd validate-genesis --home $TMP_NODE_HOME

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

echo "${SEEDS_STR}" > "${NETWORK_CONFIG_DIR}/seeds.txt"
rm -rf $TMP_NODE_HOME
