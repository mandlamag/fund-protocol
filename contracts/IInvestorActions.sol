pragma solidity >=0.4.22 <0.6.0;

contract IInvestorActions {
  function modifyAllocation(uint _allocation) external
    returns (uint _ethTotalAllocation);

  function getAvailableAllocation(address _addr) external
    returns (uint ethAvailableAllocation);

  function requestSubscription(address _addr, uint _amount) external
    returns (uint, uint);

  function cancelSubscription(address _addr) external
    returns (uint, uint, uint, uint);

  function subscribe(address _addr) external
    returns (uint, uint, uint, uint, uint, uint);
  
  function requestRedemption(address _addr, uint _shares) external
    returns (uint, uint);

  function cancelRedemption(address addr) external
    returns (uint, uint);

  function redeem(address _addr) external
    returns (uint, uint, uint, uint, uint, uint, uint);

  function liquidate(address _addr) external
    returns (uint, uint, uint, uint, uint, uint);

  function withdraw(address _addr) external
    returns (uint, uint, uint);

}