const HDWalletProvider = require('truffle-hdwallet-provider');
require('dotenv').config();
module.exports = {
  networks: {
  development: {
    host: "localhost",
    port: 8545,
    network_id: "*",
    gas: 700000000,
  },
  test: {
    host: "localhost",
    port: 7545,
    network_id: "*",
    gas: 7000000,
  },
  ropsten: {
    provider: () => {
      return new HDWalletProvider(process.env.MNEMONIC, 'https://ropsten.infura.io/v3/' + process.env.INFURA_API_KEY);
    },
    network_id: 3,
    gas: 7500000,
    confirmations: 2,
    timeoutBlocks: 400,
    skipDryRun: false // Skip dry run before migrations? (default: false for public nets )
  },
  mainnet: {
    host: "localhost",
    port: 8545,
    network_id: "1",
    gasPrice: 20000000000,
  }
  },
solc: {
        optimizer: {
            enabled: true,
            runs: 1000
        },
    }
};
