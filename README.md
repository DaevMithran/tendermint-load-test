# Tendermint-load-test
A extension of [tm-load-test](https://github.com/informalsystems/tm-load-test) to load test tendermint corresponding to number of validators

## Usage

### Load test
- Clone the repository
> `git clone https://github.com/DaevMithran/tendermint-load-test.git`

- `./manage build`
- `./manage start`


### Customizing
- `cd tendermint`
- Change the **VALIDATORS_COUNT** in gen-network-config.sh
- Modify the docker-compose.yml according to the number of validators (***To be automated***)
- Change the number of endpoints in the manage script according to the number of validators (***To be automated***)



