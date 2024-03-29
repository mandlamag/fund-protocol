const DataFeed  = artifacts.require("./DataFeed.sol");
const NavCalculator  = artifacts.require("./NavCalculator.sol");
const InvestorActions = artifacts.require("./InvestorActions.sol");
const Fund = artifacts.require("./Fund.sol");

const dataFeedInfo = require('./config/datafeed.js');

// helpers
const ethToWei = (eth) => eth * 1e18;

// DataFeed settings
const SECONDS_BETWEEN_QUERIES = 300;

const USD_ETH_EXCHANGE_RATE         = 450;
const USD_BTC_EXCHANGE_RATE         = 10000;
const USD_LTC_EXCHANGE_RATE         = 100;
const DATA_FEED_GAS_RESERVE         = 100;

// Fund settings
const FUND_NAME                     = "Solidity Capital Token";
const FUND_SYMBOL                   = "SCT";
const FUND_DECIMALS                 = 4;
const MANAGER_USD_ETH_BASIS         = 300;
const MIN_INITIAL_SUBSCRIPTION_ETH  = 20;
const MIN_SUBSCRIPTION_ETH          = 5;
const MIN_REDEMPTION_SHARES         = 100000;
const ADMIN_FEE                     = 1;
const MGMT_FEE                      = 0;
const PERFORM_FEE                   = 20;

module.exports = function(deployer, network, accounts) {

  // Accounts
  const ADMINISTRATOR = accounts[0];
  const MANAGER = accounts[0];
  const EXCHANGE = accounts[1];
  const EXCHANGE_ROPSTEN = "0xC51be93CCcD7f5ffbE429b3738a1e0500719E048"
  
  // 
  const useOraclize = true;
  const dataFeedReserve = ethToWei(DATA_FEED_GAS_RESERVE);

  if (network == "development" || network == "test") {
    deployer.deploy(
      DataFeed,
      dataFeedInfo[network].navServiceUrl,    // _queryUrl
      SECONDS_BETWEEN_QUERIES,                // _secondsBetweenQueries
      USD_ETH_EXCHANGE_RATE * 100,            // _initialUsdEthRate
      USD_BTC_EXCHANGE_RATE * 100,            // _initialUsdBtcRate
      USD_LTC_EXCHANGE_RATE * 100,            // _initialUsdLtcRate
      EXCHANGE,                               // _exchange
      { from: ADMINISTRATOR, value: dataFeedReserve }
    ).then(() =>
      deployer.deploy(
        NavCalculator, 
        DataFeed.address,
        { from: ADMINISTRATOR }
      )).then(() =>
      deployer.deploy(
        InvestorActions,
        DataFeed.address,
        { from: ADMINISTRATOR }
      )).then(() =>
      deployer.deploy(
        Fund,
        MANAGER,                        // _manager
        EXCHANGE,                       // _exchange
        NavCalculator.address,          // _navCalculator
        InvestorActions.address,        // _investorActions
        DataFeed.address,               // _dataFeed
        FUND_NAME,                      // _name
        FUND_SYMBOL,                    // _symbol
        FUND_DECIMALS,                  // _decimals
        ethToWei(MIN_INITIAL_SUBSCRIPTION_ETH).toString(), // _minInitialSubscriptionEth
        ethToWei(MIN_SUBSCRIPTION_ETH).toString(), // _minSubscriptionEth
        MIN_REDEMPTION_SHARES,          // _minRedemptionShares,
        ADMIN_FEE * 100,                // _adminFeeBps
        MGMT_FEE * 100,                 // _mgmtFeeBps
        PERFORM_FEE * 100,              // _performFeeBps
        MANAGER_USD_ETH_BASIS * 100,    // _managerUsdEthBasis
        { from: ADMINISTRATOR }
    ));
  } else {

    // Network-specific variables
    // const NAV_SERVICE_URL = dataFeedInfo[network].navServiceUrl;
    // const DATA_FEED_ADDRESS = dataFeedInfo[network].dataFeedAddress;
    const DATA_FEED_ADDRESS = "0xa0c93acce8fce9c15114cef6eb16d0ed1affaa61";
 
    // assume that DataFeed has already been deployed and has an updated value() property
    deployer.deploy(
      NavCalculator, 
      DATA_FEED_ADDRESS,
      { from: ADMINISTRATOR }
    ).then(() =>
      deployer.deploy(
        InvestorActions,
        DATA_FEED_ADDRESS,
        { from: ADMINISTRATOR }
      )).then(() =>
      deployer.deploy(
        Fund,
        MANAGER,                        // _manager
        EXCHANGE_ROPSTEN,                       // _exchange
        NavCalculator.address,          // _navCalculator
        InvestorActions.address,        // _investorActions
        DATA_FEED_ADDRESS,              // _dataFeed
        FUND_NAME,                      // _name
        FUND_SYMBOL,                    // _symbol
        FUND_DECIMALS,                  // _decimals
        MIN_INITIAL_SUBSCRIPTION_ETH, // _minInitialSubscriptionEth
        MIN_SUBSCRIPTION_ETH, // _minSubscriptionEth
        MIN_REDEMPTION_SHARES,          // _minRedemptionShares,
        ADMIN_FEE * 100,                // _adminFeeBps
        MGMT_FEE * 100,                 // _mgmtFeeBps
        PERFORM_FEE * 100,              // _performFeeBps
        MANAGER_USD_ETH_BASIS * 100,    // _managerUsdEthBasis
        { from: ADMINISTRATOR }
    ));
  }
};
