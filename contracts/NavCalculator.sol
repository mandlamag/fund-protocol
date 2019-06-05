pragma solidity >=0.4.22 <0.6.0;

import "./Fund.sol";
import "./DataFeed.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/math/Math.sol";
import "./zeppelin/DestructibleModified.sol";
/**
 * @title NavCalulator
 * @author CoinAlpha, Inc. <contact@coinalpha.com>
 *
 * @dev A module for calculating net asset value and other fund variables
 * This is a supporting module to the Fund contract that handles the logic entailed
 * in calculating an updated navPerShare and other fund-related variables given
 * time elapsed and changes in the value of the portfolio, as provided by the data feed.
 */

contract INavCalculator {
  function calculate() public
    returns (
      uint lastCalcDate,
      uint navPerShare,
      uint lossCarryforward,
      uint accumulatedMgmtFees,
      uint accumulatedAdminFees
    ) {}
}

contract NavCalculator is DestructibleModified {
  using SafeMath for uint;
  using Math for uint;

  address public fundAddress;

  // Modules
  IDataFeed public dataFeed;
  IFund fund;

  // This modifier is applied to all external methods in this contract since only
  // the primary Fund contract can use this module
  modifier onlyFund {
    require(msg.sender == fundAddress, "Access denied. Only fund");
    _;
  }

  constructor(address _dataFeed) public
  {
    dataFeed = IDataFeed(_dataFeed);
  }

  event LogNavCalculation(
    uint indexed timestamp,
    uint elapsedTime,
    uint grossAssetValueLessFees,
    uint netAssetValue,
    uint totalSupply,
    uint adminFeeInPeriod,
    uint mgmtFeeInPeriod,
    uint performFeeInPeriod,
    uint performFeeOffsetInPeriod,
    uint lossPaybackInPeriod
  );

  // Calculate nav and allocate fees
  function calculate()
    public
    onlyFund
    returns (
      uint lastCalcDate,
      uint navPerShare,
      uint lossCarryforward,
      uint accumulatedMgmtFees,
      uint accumulatedAdminFees
    )
  {

    // setting lastCalcDate for use as "now" for this function
    lastCalcDate = now;

    // Set the initial value of the variables below from the last NAV calculation
    uint netAssetValue = sharesToUsd(fund.totalSupply());
    uint elapsedTime = lastCalcDate - fund.lastCalcDate();
    lossCarryforward = fund.lossCarryforward();
    accumulatedMgmtFees = fund.accumulatedMgmtFees();
    accumulatedAdminFees = fund.accumulatedAdminFees();

    // The new grossAssetValue equals the updated value, denominated in ether, of the exchange account,
    // plus any amounts that sit in the fund contract, excluding unprocessed subscriptions
    // and unwithdrawn investor payments.
    // Removes the accumulated management and administrative fees from grossAssetValue
    uint grossAssetValueLessFees = dataFeed.value().add(fund.ethToUsd(fund.getBalance())).sub(accumulatedMgmtFees).sub(accumulatedAdminFees);

    // Calculates the base management fee accrued since the last NAV calculation
    uint mgmtFee = getAnnualFee(elapsedTime, fund.mgmtFeeBps());
    uint adminFee = getAnnualFee(elapsedTime, fund.adminFeeBps());

    // Calculate the gain/loss based on the new grossAssetValue and the old netAssetValue
    int gainLoss = int(grossAssetValueLessFees) - int(netAssetValue) - int(mgmtFee) - int(adminFee);

    uint performFee = 0;
    uint performFeeOffset = 0;
    uint lossPayback = 0;

    // if current period gain
    if (gainLoss >= 0) {
      lossPayback = Math.min(uint(gainLoss), lossCarryforward);

      // Update the lossCarryforward and netAssetValue variables
      lossCarryforward = lossCarryforward.sub(lossPayback);
      performFee = getPerformFee(uint(gainLoss).sub(lossPayback));
      netAssetValue = netAssetValue.add(uint(gainLoss)).sub(performFee);
    
    // if current period loss
    } else {
      performFeeOffset = Math.min(getPerformFee(uint(-1 * gainLoss)), accumulatedMgmtFees);
      // Update the lossCarryforward and netAssetValue variables
      lossCarryforward = lossCarryforward.add(uint(-1 * gainLoss)).sub(getGainGivenPerformFee(performFeeOffset));
      netAssetValue = netAssetValue.sub(uint(-1 * gainLoss)).add(performFeeOffset);
    }

    // Update the remaining state variables and return them to the fund contract
    accumulatedAdminFees = accumulatedAdminFees.add(adminFee);
    accumulatedMgmtFees = accumulatedMgmtFees.add(performFee).sub(performFeeOffset);
    navPerShare = toNavPerShare(netAssetValue);

    emit LogNavCalculation(lastCalcDate, elapsedTime, grossAssetValueLessFees, netAssetValue, fund.totalSupply(), adminFee, mgmtFee, performFee, performFeeOffset, lossPayback);

    return (lastCalcDate, navPerShare, lossCarryforward, accumulatedMgmtFees, accumulatedAdminFees);
  }

  // ********* ADMIN *********

  // Update the address of the Fund contract
  function setFund(address _fundAddress)
    public
    onlyOwner
  {
    fund = IFund(_fundAddress);
    fundAddress = _fundAddress;
  }

  // Update the address of the data feed contract
  function setDataFeed(address _address)
    public
    onlyOwner
  {
    dataFeed = IDataFeed(_address);
  }

  // ********* HELPERS *********

  // Returns the fee amount associated with an annual fee accumulated given time elapsed and the annual fee rate
  // Equivalent to: annual fee percentage * fund totalSupply * (seconds elapsed / seconds in a year)
  // Has the same denomination as the fund totalSupply
  function getAnnualFee(uint elapsedTime, uint annualFeeBps)
    internal 
    view 
    returns (uint feePayment) 
  {
    return annualFeeBps.mul(sharesToUsd(fund.totalSupply())).div(10000).mul(elapsedTime).div(31536000);
  }

  // Returns the performance fee for a given gain in portfolio value
  function getPerformFee(uint _usdGain) 
    internal 
    view 
    returns (uint performFee)  
  {
    return fund.performFeeBps().mul(_usdGain).div(10 ** fund.decimals());
  }

  // Returns the gain in portfolio value for a given performance fee
  function getGainGivenPerformFee(uint _performFee) 
    internal 
    view 
    returns (uint usdGain)  
  {
    return _performFee.mul(10 ** fund.decimals()).div(fund.performFeeBps());
  }

  // Converts shares to a corresponding amount of USD based on the current nav per share
  function sharesToUsd(uint _shares) 
    internal 
    view 
    returns (uint usd) 
  {
    return _shares.mul(fund.navPerShare()).div(10 ** fund.decimals());
  }

  // Converts total fund NAV to NAV per share
  function toNavPerShare(uint _balance) 
    internal 
    view 
    returns (uint) 
  {
    return _balance.mul(10 ** fund.decimals()).div(fund.totalSupply());
  }
}