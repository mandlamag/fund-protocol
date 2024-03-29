# Fund Protocol

A blockchain protocol for tokenized hedge funds.

This open-source protocol enables asset managers to create a blockchain-based vehicle that manages capital contributed by external investors. The protocol utilizes the blockchain to perform functions such as segregated asset custody, net asset value calculation, fee accounting, and management of investor in-flows and out-flows.  The goal of this project is to eliminate the setup and operational costs imposed by middlemen in traditional funds, while maximizing transparency and liquidity for investors.  

## Installation

### Ganache 

sudo npm install -g ganache-cli

```

### Truffle
Deployment and testing framework.  
```
npm install -g truffle
```


### Libraries and dependencies
```
npm install
```
## Testing

### Local
1. Run Ganache-Cli with a 1 second block time and increased block gas limit, to allow for simulation of time-based fees: `ganache-cli -b 1 -e 700000000 -l 700000000000000000000` 
2. In another Terminal window, `truffle console`
3. Run "compile" to compile 
3. `truffle test` to run all tests

### Ethereum Bridge | Oraclize
Ethereum Bridge is used for connecting to Oraclize from a non-public blockchain instance (e.g. testrpc).  This is used for testing the DataFeed contracts.

1. In a separate folder from this repo, clone the repo: `git clone https://github.com/oraclize/ethereum-bridge`
2. Setup: `cd ethereum-bridge; npm install`
3. When running ganache-cli, use the same mnemonic to keep the OraclizeAddrResolver address constant: `ganache-cli -l 7000000 -p 8545 -a 50 --mnemonic "[ganache-mnemonic]"`
4. Run: `node bridge -a 8 --dev` (`-a 8` uses the 8th testrpc account for deploying oraclize; the 8th account should not be used for any other purposes, and port 7545)
5. After starting the bridge, take note of this message:

  ```
  Please add this line to your contract constructor:

  OAR = OraclizeAddrResolverI(0x6f485C8BF6fc43eA212E93BBF8ce046C7f1cb475);
  ```
6. Add this line into DataFeel.sol

### Testnet
1. Run `geth --testnet --rpc --rpcapi eth,net,web3,personal`
2. In another Terminal window, `truffle console`
3. `web3.eth.accounts` and check that you have at least 4 accounts.  Each account should have more than 5 test eth.
4. Unlock your primary account: `web3.personal.unlockAccount(web3.eth.accounts[0], <INSERT YOUR PASSWORD HERE>, 15000)`
5. Follow manual testing workflows in `js/Fund-test.js`
