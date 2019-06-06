import HDWalletProvider from 'truffle-hdwallet-provider';
require('dotenv').config();
export const networks = {
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
    gas: 5500000,
    confirmations: 2,
    timeoutBlocks: 400,
    skipDryRun: true // Skip dry run before migrations? (default: false for public nets )
  },
  mainnet: {
    host: "localhost",
    port: 8545,
    network_id: "1",
    gasPrice: 20000000000,
  }
};
