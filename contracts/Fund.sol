pragma solidity >=0.4.22 <0.6.0;

import "./NavCalculator.sol";
import "./InvestorActions.sol";
import "./DataFeed.sol";
import "./IFund.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./zeppelin/DestructiblePausable.sol";

contract Fund is DestructiblePausable, IFund{
  using SafeMath for uint;

  // Constants set at contract inception
  string  public name;                         // fund name
  string  public symbol;                       // Ethereum token symbol
  uint    public decimals;                     // number of decimals used to display navPerShare
  uint    public minInitialSubscriptionEth;    // minimum amount of ether that a new investor can subscribe
  uint    public minSubscriptionEth;           // minimum amount of ether that an existing investor can subscribe
  uint    public minRedemptionShares;          // minimum amount of shares that an investor can request be redeemed
  uint    public adminFeeBps;                  // annual administrative fee, if any, in basis points
  uint    public mgmtFeeBps;                   // annual base management fee, if any, in basis points
  uint    public performFeeBps;                // performance management fee earned on gains, in basis points
  address public manager;                      // address of the manager account allowed to withdraw base and performance management fees
  address payable exchange;                     // address of the exchange account where the manager conducts trading.

  // Variables that are updated after each call to the calcNav function
  uint    public lastCalcDate;
  uint    public navPerShare;
  uint    public accumulatedMgmtFees;
  uint    public accumulatedAdminFees;
  uint    public lossCarryforward;

  // Fund Balances
  uint    public totalEthPendingSubscription;    // total subscription requests not yet processed by the manager, denominated in ether
  uint    public totalSharesPendingRedemption;   // total redemption requests not yet processed by the manager, denominated in shares
  uint    public totalEthPendingWithdrawal;      // total payments not yet withdrawn by investors, denominated in shares
  uint    public totalSupply;                    // total number of shares outstanding

  // Modules: where possible, fund logic is delegated to the module contracts below, so that they can be patched and upgraded after contract deployment
  INavCalculator   public navCalculator;         // calculating net asset value
  IInvestorActions public investorActions;       // performing investor actions such as subscriptions, redemptions, and withdrawals
  IDataFeed       public dataFeed;              // fetching external data like total portfolio value and exchange rates

  // This struct tracks fund-related balances for a specific investor address
  struct Investor {
    uint ethTotalAllocation;                  // Total allocation allowed for an investor, denominated in ether
    uint ethPendingSubscription;              // Ether deposited by an investor not yet proceessed by the manager
    uint sharesOwned;                         // Balance of shares owned by an investor.  For investors, this is identical to the ERC20 balances variable.
    uint sharesPendingRedemption;             // Redemption requests not yet processed by the manager
    uint ethPendingWithdrawal;                // Payments available for withdrawal by an investor
  }
  mapping (address => Investor) public investors;
  address[] investorAddresses;

  // Events
  event LogAllocationModification(address indexed investor, uint eth);
  event LogSubscriptionRequest(address indexed investor, uint eth, uint usdEthBasis);
  event LogSubscriptionCancellation(address indexed investor);
  event LogSubscription(address indexed investor, uint shares, uint navPerShare, uint usdEthExchangeRate);
  event LogRedemptionRequest(address indexed investor, uint shares);
  event LogRedemptionCancellation(address indexed investor);
  event LogRedemption(address indexed investor, uint shares, uint navPerShare, uint usdEthExchangeRate);
  event LogLiquidation(address indexed investor, uint shares, uint navPerShare, uint usdEthExchangeRate);
  event LogWithdrawal(address indexed investor, uint eth);
  event LogNavSnapshot(uint indexed timestamp, uint navPerShare, uint lossCarryforward, uint accumulatedMgmtFees, uint accumulatedAdminFees);
  event LogManagerAddressChanged(address oldAddress, address newAddress);
  event LogExchangeAddressChanged(address oldAddress, address newAddress);
  event LogNavCalculatorModuleChanged(address oldAddress, address newAddress);
  event LogInvestorActionsModuleChanged(address oldAddress, address newAddress);
  event LogDataFeedModuleChanged(address oldAddress, address newAddress);
  event LogTransferToExchange(uint amount);
  event LogTransferFromExchange(uint amount);
  event LogManagementFeeWithdrawal(uint amountInEth, uint usdEthExchangeRate);
  event LogAdminFeeWithdrawal(uint amountInEth, uint usdEthExchangeRate);

  // Modifiers
  modifier onlyFromExchange {
    require(msg.sender == exchange, "Access denied. Only exchange can access");
    _;
  }

  modifier onlyManager {
    require(msg.sender == manager, "Access denied. Only manager can access");
    _;
  }

  /**
  * @dev Constructor function that creates a fund
  * This function is payable and treats any ether sent as part of the manager's own investment in the fund.
  */
constructor(
    address _manager,
    address payable _exchange,
    address _navCalculator,
    address _investorActions,
    address _dataFeed,
    string memory  _name,
    string memory  _symbol,
    uint    _decimals,
    uint256    _minInitialSubscriptionEth,
    uint256    _minSubscriptionEth,
    uint256    _minRedemptionShares,
    uint256    _adminFeeBps,
    uint256    _mgmtFeeBps,
    uint256    _performFeeBps,
    uint256    _managerUsdEthBasis
  ) public
  {
    // Constants
    name = _name;
    symbol = _symbol;
    decimals = _decimals;
    minSubscriptionEth = _minSubscriptionEth;
    minInitialSubscriptionEth = _minInitialSubscriptionEth;
    minRedemptionShares = _minRedemptionShares;
    adminFeeBps = _adminFeeBps;
    mgmtFeeBps = _mgmtFeeBps;
    performFeeBps = _performFeeBps;

    // Set the addresses of other wallets/contracts with which this contract interacts
    manager = _manager;
    exchange = _exchange;
    navCalculator = INavCalculator(_navCalculator);
    investorActions = IInvestorActions(_investorActions);
    dataFeed = IDataFeed(_dataFeed);

    // Set the initial net asset value calculation variables
    lastCalcDate = now;
    navPerShare = 10 ** decimals;

    // Treat existing funds in the exchange relay and the portfolio as the manager's own investment
    // Amounts are included in fee calculations since the fees are going to the manager anyway.
    // TestRPC: dataFeed.value should be zero
    // TestNet: ensure that the exchange account balance is zero or near zero
    uint managerShares = ethToShares(exchange.balance) + dataFeed.value();
    totalSupply = managerShares;
    investors[manager].ethTotalAllocation = sharesToEth(managerShares);
    investors[manager].sharesOwned = managerShares;

    emit LogAllocationModification(manager, sharesToEth(managerShares));
    emit LogSubscription(manager, managerShares, navPerShare, _managerUsdEthBasis);
  }

  // [INVESTOR METHOD] Returns the variables contained in the Investor struct for a given address
  function getInvestor(address _addr)
    external
    view
    returns (
      uint ethTotalAllocation,
      uint ethPendingSubscription,
      uint sharesOwned,
      uint sharesPendingRedemption,
      uint ethPendingWithdrawal
    )
  {
    Investor storage investor = investors[_addr];
    return (investor.ethTotalAllocation, investor.ethPendingSubscription,
     investor.sharesOwned, investor.sharesPendingRedemption, investor.ethPendingWithdrawal);
  }

  // ********* SUBSCRIPTIONS *********

  // Modifies the max investment limit allowed for an investor
  // Delegates logic to the InvestorActions module
  function modifyAllocation(address _investorAddress, uint _allocation)
    external
    returns (bool success)
  {
    // Adds the investor to investorAddresses array if their previous allocation was zero
    if (investors[_investorAddress].ethTotalAllocation == 0) {

      // Check if address already exists before adding
      bool addressExists;
      for (uint i = 0; i < investorAddresses.length; i++) {
        if (_investorAddress == investorAddresses[i]) {
          addressExists = true;
          i = investorAddresses.length;
        }
      }
      if (!addressExists) {
        investorAddresses.push(_investorAddress);
      }
    }
    uint ethTotalAllocation = investorActions.modifyAllocation(_allocation);
    investors[_investorAddress].ethTotalAllocation = ethTotalAllocation;

    emit LogAllocationModification(_investorAddress, _allocation);
    return true;
  }

  // [INVESTOR METHOD] External wrapper for the getAvailableAllocation function in InvestorActions
  // Delegates logic to the InvestorActions module
  function getAvailableAllocation(address _addr)
    external
    returns (uint ethAvailableAllocation)
  {
    return investorActions.getAvailableAllocation(_addr);
  }

  // Non-payable fallback function so that any attempt to send ETH directly to the contract is thrown
  function ()
    external
    payable
    onlyFromExchange
  { this.remitFromExchange(); }

  // [INVESTOR METHOD] Issue a subscription request by transferring ether into the fund
  // Delegates logic to the InvestorActions module
  // usdEthBasis is expressed in USD cents.  For example, for a rate of 300.01, _usdEthBasis = 30001
  function requestSubscription(uint _usdEthBasis)
    external
    whenNotPaused
    payable
    returns (bool success)
  {
    (uint _ethPendingSubscription, uint _totalEthPendingSubscription) = investorActions.requestSubscription(msg.sender, msg.value);
    investors[msg.sender].ethPendingSubscription = _ethPendingSubscription;
    totalEthPendingSubscription = _totalEthPendingSubscription;

    emit LogSubscriptionRequest(msg.sender, msg.value, _usdEthBasis);
    return true;
  }

  // [INVESTOR METHOD] Cancels a subscription request
  // Delegates logic to the InvestorActions module
  function cancelSubscription()
    external
    whenNotPaused
    returns (bool success)
  {
    (uint _ethPendingSubscription,uint _ethPendingWithdrawal,uint _totalEthPendingSubscription,
    uint _totalEthPendingWithdrawal) = investorActions.cancelSubscription(msg.sender);
    investors[msg.sender].ethPendingSubscription = _ethPendingSubscription;
    investors[msg.sender].ethPendingWithdrawal = _ethPendingWithdrawal;
    totalEthPendingSubscription = _totalEthPendingSubscription;
    totalEthPendingWithdrawal = _totalEthPendingWithdrawal;

    emit LogSubscriptionCancellation(msg.sender);

    return true;
  }

  // Fulfill one subscription request
  // Delegates logic to the InvestorActions module
  function subscribe(address _addr)
    internal
    returns (bool success)
  {
   (uint ethPendingSubscription, uint sharesOwned, uint shares, uint transferAmount,
    uint _totalSupply, uint _totalEthPendingSubscription) = investorActions.subscribe(_addr);
    investors[_addr].ethPendingSubscription = ethPendingSubscription;
    investors[_addr].sharesOwned = sharesOwned;
    totalSupply = _totalSupply;
    totalEthPendingSubscription = _totalEthPendingSubscription;

    exchange.transfer(transferAmount);
    emit LogSubscription(_addr, shares, navPerShare, dataFeed.usdEth());
    emit LogTransferToExchange(transferAmount);
    return true;
  }
  function subscribeInvestor(address _addr)
    external
    onlyOwner
    returns (bool success)
  {
    subscribe(_addr);
    return true;
  }

  // Fulfill all outstanding subsription requests
  // *Note re: gas - if there are too many investors (i.e. this process exceeds gas limits),
  //                 fallback is to subscribe() each individually
  function fillAllSubscriptionRequests()
    external
    onlyOwner
    returns (bool allSubscriptionsFilled)
  {
    for (uint8 i = 0; i < investorAddresses.length; i++) {
      address addr = investorAddresses[i];
      if (investors[addr].ethPendingSubscription > 0) {
        subscribe(addr);
      }
    }
    return true;
  }

  // ********* REDEMPTIONS *********

  // Returns the total redemption requests not yet processed by the manager, denominated in ether
  function totalEthPendingRedemption()
    external
    view
    returns (uint)
  {
    return this.sharesToEth(totalSharesPendingRedemption);
  }

  // [INVESTOR METHOD] Issue a redemption request
  // Delegates logic to the InvestorActions module
  function requestRedemption(uint _shares)
    external
    whenNotPaused
    returns (bool success)
  {
    (uint sharesPendingRedemption,uint  _totalSharesPendingRedemption) = investorActions.requestRedemption(msg.sender, _shares);
    investors[msg.sender].sharesPendingRedemption = sharesPendingRedemption;
    totalSharesPendingRedemption = _totalSharesPendingRedemption;

    emit LogRedemptionRequest(msg.sender, _shares);
    return true;
  }

  // [INVESTOR METHOD] Cancels a redemption request
  // Delegates logic to the InvestorActions module
  function cancelRedemption()
    external
    returns (bool success)
  {
    (uint _sharesPendingRedemption,uint  _totalSharesPendingRedemption) = investorActions.cancelRedemption(msg.sender);
    investors[msg.sender].sharesPendingRedemption = _sharesPendingRedemption;
    totalSharesPendingRedemption = _totalSharesPendingRedemption;

    emit LogRedemptionCancellation(msg.sender);
    return true;
  }

  // Fulfill one redemption request
  // Delegates logic to the InvestorActions module
  // Fulfill one sharesPendingRedemption request
  function redeem(address _addr)
    internal
    returns (bool success)
  {
   (uint sharesOwned,uint  sharesPendingRedemption,uint ethPendingWithdrawal, uint shares,
   uint _totalSupply, uint _totalSharesPendingRedemption, uint _totalEthPendingWithdrawal) = investorActions.redeem(_addr);
    investors[_addr].sharesOwned = sharesOwned;
    investors[_addr].sharesPendingRedemption = sharesPendingRedemption;
    investors[_addr].ethPendingWithdrawal = ethPendingWithdrawal;
    totalSupply = _totalSupply;
    totalSharesPendingRedemption = _totalSharesPendingRedemption;
    totalEthPendingWithdrawal = _totalEthPendingWithdrawal;

    emit LogRedemption(_addr, shares, navPerShare, dataFeed.usdEth());
    return true;
  }
  function redeemInvestor(address _addr)
    external
    onlyOwner
    returns (bool success)
  {
    redeem(_addr);
    return true;
  }

  // Fulfill all outstanding redemption requests
  // Delegates logic to the InvestorActions module
  // See note on gas/for loop in fillAllSubscriptionRequests
  function fillAllRedemptionRequests()
    external
    onlyOwner
    returns (bool success)
  {
    require(this.totalEthPendingRedemption() <= address(this).balance.sub(totalEthPendingWithdrawal).sub(totalEthPendingSubscription),
    "invalid total eth pending redemption");

    for (uint i = 0; i < investorAddresses.length; i++) {
      address addr = investorAddresses[i];
      if (investors[addr].sharesPendingRedemption > 0) {
        redeem(addr);
      }
    }
    return true;
  }

  // ********* LIQUIDATIONS *********

  // Converts all of an investor's shares to ether and makes it available for withdrawal.  Also makes the investor's allocation zero to prevent future investment.
  // Delegates logic to the InvestorActions module
  function liquidate(address _addr)
    internal
    returns (bool success)
  {
    (uint ethPendingWithdrawal, uint shares, uint _totalEthPendingSubscription,
    uint _totalSharesPendingRedemption,uint _totalSupply,uint _totalEthPendingWithdrawal) = investorActions.liquidate(_addr);

    investors[_addr].ethTotalAllocation = 0;
    investors[_addr].ethPendingSubscription = 0;
    investors[_addr].sharesOwned = 0;
    investors[_addr].sharesPendingRedemption = 0;
    investors[_addr].ethPendingWithdrawal = ethPendingWithdrawal;
    totalEthPendingSubscription = _totalEthPendingSubscription;
    totalSharesPendingRedemption = _totalSharesPendingRedemption;
    totalSupply = _totalSupply;
    totalEthPendingWithdrawal = _totalEthPendingWithdrawal;

    emit LogLiquidation(_addr, shares, navPerShare, dataFeed.usdEth());
    return true;
  }
  function liquidateInvestor(address _addr)
    external
    onlyOwner
    returns (bool success)
  {
    liquidate(_addr);
    return true;
  }

  // Liquidates all investors
  // See note on gas/for loop in fillAllSubscriptionRequests
  function liquidateAllInvestors()
    external
    onlyOwner
    returns (bool success)
  {
    for (uint8 i = 0; i < investorAddresses.length; i++) {
      address addr = investorAddresses[i];
      liquidate(addr);
    }
    return true;
  }

  // ********* WITHDRAWALS *********

  // Withdraw payment in the ethPendingWithdrawal balance
  // Delegates logic to the InvestorActions module
  function withdrawPayment()
    external
    whenNotPaused
    returns (bool success)
  {
    (uint payment, uint ethPendingWithdrawal, uint _totalEthPendingWithdrawal) = investorActions.withdraw(msg.sender);
    investors[msg.sender].ethPendingWithdrawal = ethPendingWithdrawal;
    totalEthPendingWithdrawal = _totalEthPendingWithdrawal;

    msg.sender.transfer(payment);

    emit LogWithdrawal(msg.sender, payment);
    return true;
  }

  // ********* NAV CALCULATION *********

  // Calculate and update NAV per share, lossCarryforward (the amount of losses that the fund to make up in order to start earning performance fees),
  // and accumulated management fee balaces.
  // Delegates logic to the NavCalculator module
  function calcNav()
    external
    onlyOwner
    returns (bool success)
  {
     (
      uint256 _lastCalcDate,
      uint _navPerShare,
      uint _lossCarryforward,
      uint _accumulatedMgmtFees,
      uint _accumulatedAdminFees
    ) = navCalculator.calculate();

    lastCalcDate = _lastCalcDate;
    navPerShare = _navPerShare;
    lossCarryforward = _lossCarryforward;
    accumulatedMgmtFees = _accumulatedMgmtFees;
    accumulatedAdminFees = _accumulatedAdminFees;

    emit LogNavSnapshot(lastCalcDate, navPerShare, lossCarryforward, accumulatedMgmtFees, accumulatedAdminFees);
    return true;
  }

  // ********* FEES *********

  // Withdraw management fees from the contract
  function withdrawMgmtFees()
    external
    whenNotPaused
    onlyManager
    returns (bool success)
  {
    uint ethWithdrawal = this.usdToEth(accumulatedMgmtFees);
    require(ethWithdrawal <= getBalance(), "Insuffient balance to perform this action");

    address payable payee = msg.sender;

    accumulatedMgmtFees = 0;
    payee.transfer(ethWithdrawal);
    emit LogManagementFeeWithdrawal(ethWithdrawal, dataFeed.usdEth());
    return true;
  }

  // Withdraw management fees from the contract
  function withdrawAdminFees()
    external
    whenNotPaused
    onlyOwner
    returns (bool success)
  {
    uint ethWithdrawal = this.usdToEth(accumulatedAdminFees);
    require(ethWithdrawal <= getBalance(), "Insuffient balance to perform this action");

    address payable payee = msg.sender;

    accumulatedMgmtFees = 0;
    payee.transfer(ethWithdrawal);
    emit LogAdminFeeWithdrawal(ethWithdrawal, dataFeed.usdEth());
    return true;
  }

  // ********* CONTRACT MAINTENANCE *********

  // Returns a list of all investor addresses
  function getInvestorAddresses()
    external
    view
    onlyOwner
    returns (address[] memory)
  {
    return investorAddresses;
  }

  // Update the address of the manager account
  function setManager(address _addr)
    external
    whenNotPaused
    onlyManager
    returns (bool success)
  {
    require(_addr != address(0), "Valid address is required!");
    address old = manager;
    manager = _addr;
    emit LogManagerAddressChanged(old, _addr);
    return true;
  }

  // Update the address of the exchange account
  function setExchange(address payable _addr)
    external
    onlyOwner
    returns (bool success)
  {
    require(_addr != address(0), "Valid address is required!");
    address old = exchange;
    exchange = _addr;
    emit LogExchangeAddressChanged(old, _addr);
    return true;
  }

  // Update the address of the NAV Calculator module
  function setNavCalculator(address _addr)
    external
    onlyOwner
    returns (bool success)
  {
    require(_addr != address(0), "Valid address is required!");
    INavCalculator old = navCalculator;
    navCalculator = INavCalculator(_addr);
    emit LogNavCalculatorModuleChanged(address(old), _addr);
    return true;
  }

  // Update the address of the Investor Actions module
  function setInvestorActions(address _addr)
    external
    onlyOwner
    returns (bool success)
  {
    require(_addr != address(0), "Valid address is required!");
    IInvestorActions old = investorActions;
    investorActions = IInvestorActions(_addr);
    emit LogInvestorActionsModuleChanged(address(old), _addr);
    return true;
  }

  // Update the address of the data feed contract
  function setDataFeed(address _addr)
    external
    onlyOwner
    returns (bool success)
  {
    require(_addr != address(0), "Valid address is required!");
    IDataFeed old = dataFeed;
    dataFeed = IDataFeed(_addr);
    emit LogDataFeedModuleChanged(address(old), _addr);
    return true;
  }

  // Utility function for exchange to send funds to contract
  function remitFromExchange()
    external
    payable
    onlyFromExchange
    returns (bool success)
  {
    emit LogTransferFromExchange(msg.value);
    return true;
  }

  // Utility function for contract to send funds to exchange
  function sendToExchange(uint amount)
    external
    onlyOwner
    returns (bool success)
  {
    require(amount <= address(this).balance.sub(totalEthPendingSubscription).sub(totalEthPendingWithdrawal),
     "Funds cannot be greater than your balance");
    exchange.transfer(amount);
    emit LogTransferToExchange(amount);
    return true;
  }

  // ********* HELPERS *********

  // Converts ether to a corresponding number of shares based on the current nav per share
  function ethToShares(uint _eth)
    public
    view
    returns (uint shares)
  {
    return ethToUsd(_eth).mul(10 ** decimals).div(navPerShare);
  }

  // Converts shares to a corresponding amount of ether based on the current nav per share
  function sharesToEth(uint _shares)
    public
    view
    returns (uint ethAmount)
  {
    return usdToEth(_shares.mul(navPerShare).div(10 ** decimals));
  }

  function usdToEth(uint _usd)
    public
    view
    returns (uint eth)
  {
    return _usd.mul(1e18).div(dataFeed.usdEth());
  }

  function ethToUsd(uint _eth)
    public
    view
    returns (uint usd)
  {
    return _eth.mul(dataFeed.usdEth()).div(1e18);
  }

  // Returns the fund's balance less pending subscriptions and withdrawals
  function getBalance()
    public
    view
    returns (uint ethAmount)
  {
    return address(this).balance.sub(totalEthPendingSubscription).sub(totalEthPendingWithdrawal);
  }
}