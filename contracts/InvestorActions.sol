pragma solidity >=0.4.22 <0.6.0;

import "./IFund.sol";
import "./IInvestorActions.sol";
import "./DataFeed.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./zeppelin/DestructibleModified.sol";

contract InvestorActions is DestructibleModified, IInvestorActions {
  using SafeMath for uint;

  address public fundAddress;

  // Modules
  IDataFeed public dataFeed;
  IFund fund;

  constructor(address _dataFeed) public
  {
    dataFeed = IDataFeed(_dataFeed);
  }

  // This modifier is applied to all external methods in this contract since only
  // the primary Fund contract can use this module
  modifier onlyFund {
    require(msg.sender == fundAddress, "Access denied. Only fund allowed");
    _;
  }
  // Modifies the max investment limit allowed for an investor and overwrites the past limit
  // Used for both whitelisting a new investor and modifying an existing investor's allocation
  function modifyAllocation(uint _allocation)
    external
    onlyFund
    returns (uint _ethTotalAllocation)
  {
    require(_allocation > 0, "allocation invalid. Must more than 0");
    return _allocation;
  }

  // Get the remaining available amount in Ether that an investor can subscribe for
  function getAvailableAllocation(address _addr)
    external
    onlyFund
    returns (uint ethAvailableAllocation)
  {
    (uint256 ethTotalAllocation, uint256 ethPendingSubscription,
     uint256 sharesOwned,,) = fund.getInvestor(_addr);

    uint ethFilledAllocation = ethPendingSubscription.add(fund.sharesToEth(sharesOwned));

    if (ethTotalAllocation > ethFilledAllocation) {
      return ethTotalAllocation.sub(ethFilledAllocation);
    } else {
      return 0;
    }
  }

  // Register an investor's subscription request, after checking that
  // 1) the requested amount exceeds the minimum subscription amount and
  // 2) the investor's total allocation is not exceeded
  function requestSubscription(address _addr, uint _amount)
    external
    onlyFund
    returns (uint, uint)
  {
    (uint256 ethTotalAllocation, uint256 ethPendingSubscription,
     uint256 sharesOwned,uint256 sharesPendingRedemption, uint256 ethPendingWithdrawal) = fund.getInvestor(_addr);


    if (sharesOwned == 0) {
      require(_amount >= fund.minInitialSubscriptionEth(), "Error: Amount less than required minimum initial subscription");
    } else {
      require(_amount >= fund.minSubscriptionEth(), "Error: Amount less than required minimum subscription");
    }
    require(ethTotalAllocation >= _amount.add(ethPendingSubscription).add(fund.sharesToEth(sharesOwned)),
     "Total ETH allocation is not greater than added values");

    return (ethPendingSubscription.add(_amount),                                 // new investor.ethPendingSubscription
            fund.totalEthPendingSubscription().add(_amount)                      // new totalEthPendingSubscription
           );
  }

  // Handles an investor's subscription cancellation, after checking that
  // the fund balance has enough ether to cover the withdrawal.
  // The amount is then moved from ethPendingSubscription to ethPendingWithdrawal
  // so that it can be withdrawn by the investor.
  function cancelSubscription(address _addr)
    external
    onlyFund
    returns (uint, uint, uint, uint)
  {
    (uint256 ethTotalAllocation, uint256 ethPendingSubscription,
     uint256 sharesOwned,uint256 sharesPendingRedemption, uint256 ethPendingWithdrawal) = fund.getInvestor(_addr);

    uint otherPendingSubscriptions = fund.totalEthPendingSubscription().sub(ethPendingSubscription);
    require(ethPendingSubscription <= address(fund).balance.sub(fund.totalEthPendingWithdrawal()).sub(otherPendingSubscriptions));

    return (0,                                                                  // new investor.ethPendingSubscription
            ethPendingWithdrawal.add(ethPendingSubscription),                   // new investor.ethPendingWithdrawal
            fund.totalEthPendingSubscription().sub(ethPendingSubscription),     // new totalEthPendingSubscription
            fund.totalEthPendingWithdrawal().add(ethPendingSubscription)        // new totalEthPendingWithdrawal
           );
  }

  // Processes an investor's subscription request and mints new shares at the current navPerShare
  function subscribe(address _addr)
    external
    onlyFund
    returns (uint, uint, uint, uint, uint, uint)
  {
    (uint256 ethTotalAllocation, uint256 ethPendingSubscription,
     uint256 sharesOwned,uint256 sharesPendingRedemption, uint256 ethPendingWithdrawal) = fund.getInvestor(_addr);

    // Check that the fund balance has enough ether because the Fund contract's subscribe
    // function that calls this one will immediately transfer the subscribed amount of ether
    // to the exchange account upon function return
    uint otherPendingSubscriptions = fund.totalEthPendingSubscription().sub(ethPendingSubscription);
    require(ethPendingSubscription <=
    address(fund).balance.sub(fund.totalEthPendingWithdrawal()).sub(otherPendingSubscriptions), "Eth Pending Subscription invalid");
    uint shares = fund.ethToShares(ethPendingSubscription);

    return (0,                                                                  // new investor.ethPendingSubscription
            sharesOwned.add(shares),                                            // new investor.sharesOwned
            shares,                                                             // shares minted
            ethPendingSubscription,                                             // amount transferred to exchange
            fund.totalSupply().add(shares),                                     // new totalSupply
            fund.totalEthPendingSubscription().sub(ethPendingSubscription)      // new totalEthPendingSubscription
           );
  }

  // Register an investor's redemption request, after checking that
  // 1) the requested amount exceeds the minimum redemption amount and
  // 2) the investor can't redeem more than the shares they own
  function requestRedemption(address _addr, uint _shares)
    external
    onlyFund
    returns (uint, uint)
  {
    require(_shares >= fund.minRedemptionShares());

    (uint256 ethTotalAllocation, uint256 ethPendingSubscription,
     uint256 sharesOwned,uint256 sharesPendingRedemption, uint256 ethPendingWithdrawal) = fund.getInvestor(_addr);



    // Investor's shares owned should be larger than their existing redemption requests
    // plus this new redemption request
    require(sharesOwned >= _shares.add(sharesPendingRedemption));

    return (sharesPendingRedemption.add(_shares),                                // new investor.sharesPendingRedemption
            fund.totalSharesPendingRedemption().add(_shares)                     // new totalSharesPendingRedemption
           );
  }

  // Handles an investor's redemption cancellation, after checking that
  // the fund balance has enough ether to cover the withdrawal.
  // The amount is then moved from sharesPendingRedemption
  function cancelRedemption(address _addr)
    external
    onlyFund
    returns (uint, uint)
  {
    (uint256 ethTotalAllocation, uint256 ethPendingSubscription,
     uint256 sharesOwned,uint256 sharesPendingRedemption, uint256 ethPendingWithdrawal) = fund.getInvestor(_addr);

    // Check that the total shares pending redemption is greator than the investor's shares pending redemption
    assert(fund.totalSharesPendingRedemption() >= sharesPendingRedemption);

    return (0,                                                                  // new investor.sharesPendingRedemption
            fund.totalSharesPendingRedemption().sub(sharesPendingRedemption)    // new totalSharesPendingRedemption
           );
  }

  // Processes an investor's redemption request and annilates their shares at the current navPerShare
  function redeem(address _addr)
    external
    onlyFund
    returns (uint, uint, uint, uint, uint, uint, uint)
  {
    (uint256 ethTotalAllocation, uint256 ethPendingSubscription,
     uint256 sharesOwned,uint256 sharesPendingRedemption, uint256 ethPendingWithdrawal) = fund.getInvestor(_addr);

    // Check that the fund balance has enough ether because after this function is processed, the ether
    // equivalent amount can be withdrawn by the investor
    uint amount = fund.sharesToEth(sharesPendingRedemption);
    require(amount <= address(fund).balance.sub(fund.totalEthPendingSubscription()).sub(fund.totalEthPendingWithdrawal()));

    return (sharesOwned.sub(sharesPendingRedemption),                           // new investor.sharesOwned
            0,                                                                  // new investor.sharesPendingRedemption
            ethPendingWithdrawal.add(amount),                                   // new investor.ethPendingWithdrawal
            sharesPendingRedemption,                                            // shares annihilated
            fund.totalSupply().sub(sharesPendingRedemption),                    // new totalSupply
            fund.totalSharesPendingRedemption().sub(sharesPendingRedemption),   // new totalSharesPendingRedemption
            fund.totalEthPendingWithdrawal().add(amount)                        // new totalEthPendingWithdrawal
          );
  }

  // Converts all of an investor's shares to ether and makes it available for withdrawal.  Also makes the investor's allocation zero to prevent future investment.
  function liquidate(address _addr)
    external
    onlyFund
    returns (uint, uint, uint, uint, uint, uint)
  {
    (uint256 ethTotalAllocation, uint256 ethPendingSubscription,
     uint256 sharesOwned,uint256 sharesPendingRedemption, uint256 ethPendingWithdrawal) = fund.getInvestor(_addr);

    // Check that the fund balance has enough ether because after this function is processed, the ether
    // equivalent amount can be withdrawn by the investor.  The fund balance less total withdrawals and other
    // investors' pending subscriptions should be larger than or equal to the liquidated amount.
    uint otherPendingSubscriptions = fund.totalEthPendingSubscription().sub(ethPendingSubscription);
    uint amount = fund.sharesToEth(sharesOwned).add(ethPendingSubscription);
    require(amount <= address(fund).balance.sub(fund.totalEthPendingWithdrawal()).sub(otherPendingSubscriptions));

    return (ethPendingWithdrawal.add(amount),                                   // new investor.ethPendingWithdrawal
            sharesOwned,                                                        // shares annihilated
            fund.totalEthPendingSubscription().sub(ethPendingSubscription),     // new totalEthPendingSubscription
            fund.totalSharesPendingRedemption().sub(sharesPendingRedemption),   // new totalSharesPendingRedemption
            fund.totalSupply().sub(sharesOwned),                                // new totalSupply
            fund.totalEthPendingWithdrawal().add(amount)                        // new totalEthPendingWithdrawal
           );
  }

  // Handles a withdrawal by an investor
  function withdraw(address _addr)
    external
    onlyFund
    returns (uint, uint, uint)
  {
    (uint256 ethTotalAllocation, uint256 ethPendingSubscription,
     uint256 sharesOwned,uint256 sharesPendingRedemption, uint256 ethPendingWithdrawal) = fund.getInvestor(_addr);

    // Check that the fund balance has enough ether to cover the withdrawal after subtracting pending subscriptions
    // and other investors' withdrawals
    require(ethPendingWithdrawal != 0);
    uint otherInvestorPayments = fund.totalEthPendingWithdrawal().sub(ethPendingWithdrawal);
    require(ethPendingWithdrawal <= address(fund).balance.sub(fund.totalEthPendingSubscription()).sub(otherInvestorPayments));

    return (ethPendingWithdrawal,                                               // payment to be sent
            0,                                                                  // new investor.ethPendingWithdrawal
            fund.totalEthPendingWithdrawal().sub(ethPendingWithdrawal)          // new totalEthPendingWithdrawal
            );
  }

  // ********* ADMIN *********

  // Update the address of the Fund contract
  function setFund(address _fundAddress)
    external
    onlyOwner
    returns (bool success)
  {
    fund = IFund(_fundAddress);
    fundAddress = _fundAddress;
    return true;
  }

  // Update the address of the data feed contract
  function setDataFeed(address _address) 
    external
    onlyOwner 
    returns (bool success)
  {
    dataFeed = IDataFeed(_address);
    return true;
  }
}
