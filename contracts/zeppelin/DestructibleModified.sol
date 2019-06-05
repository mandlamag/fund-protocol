pragma solidity >=0.4.22 <0.6.0;


import "./OwnableModified.sol";


/**
 * @title DestructibleModified
 * @author CoinAlpha, Inc. <contact@coinalpha.com>
 * 
 * @dev This modifies the OpenZeppelin Destructible contract to allow for 2 owner addresses
 * Original contract: https://github.com/OpenZeppelin/zeppelin-solidity/blob/master/contracts/lifecycle/Destructible.sol
 * Base contract that can be destroyed by owner. All funds in contract will be sent to the first owner.
 */
contract DestructibleModified is OwnableModified {

  constructor() public payable { }

  /**
   * @dev Transfers the current balance to the owner and terminates the contract. 
   */
  function destroy() public onlyOwner {
    selfdestruct(owners[0]);
  }

  function destroyAndSend(address payable _recipient) public onlyOwner {
    selfdestruct(_recipient);
  }
}
