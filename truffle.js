module.exports = {
  networks: {
    development: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "*", // Match any network id
      gas: 6000000000,   // <--- Twice as much
      gasPrice: 10000000000,
    },
    test: {
      host: "localhost",
      port: 7545,
      network_id: "*", // Match any network id
      gas: 7000000,
    },
    ropsten: {
      host: "localhost",
      port: 8545,
      network_id: "3",
      gas: 7000000,
      gasPrice: 20000000000, // 20 GWei
    },
    mainnet: {
      host: "localhost",
      port: 8545,
      network_id: "1",
      gasPrice: 20000000000, // 20 GWei
    }
  }
};
