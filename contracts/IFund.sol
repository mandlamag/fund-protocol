pragma solidity >=0.4.22 <0.6.0;

contract IFund {
  uint256    public decimals;
  uint256    public minInitialSubscriptionEth;
  uint256    public minSubscriptionEth;
  uint256    public minRedemptionShares;
  uint256    public totalEthPendingSubscription;
  uint256    public totalEthPendingWithdrawal;
  uint256    public totalSharesPendingRedemption;
  uint256    public totalSupply;

  uint    public adminFeeBps;
  uint    public mgmtFeeBps;
  uint    public performFeeBps;

  uint    public lastCalcDate;
  uint    public navPerShare;
  uint    public accumulatedMgmtFees;
  uint    public accumulatedAdminFees;
  uint    public lossCarryforward;

  function getInvestor(address _addr)
    external
    view
    returns (
      uint ethTotalAllocation,
      uint ethPendingSubscription,
      uint sharesOwned,
      uint sharesPendingRedemption,
      uint ethPendingWithdrawal
    );

  function usdToEth(uint _usd)
    public
    view
    returns (uint eth);

  function ethToUsd(uint _eth)
    public
    view
    returns (uint usd);

  function ethToShares(uint _eth)
    public
    view
    returns (uint shares);

  function sharesToEth(uint _shares)
    public
    view
    returns (uint ethAmount);

  function getBalance()
    public
    view
    returns (uint ethAmount);
}
