pragma solidity >=0.4.22 <0.6.0;


/**
 * @title OwnableModified
 * @author CoinAlpha, Inc. <contact@coinalpha.com>
 * 
 * @dev This modifies the OpenZeppelin Ownable contract to allow for 2 owner addresses.
 * Original contract: https://github.com/OpenZeppelin/zeppelin-solidity/blob/master/contracts/ownership/Ownable.sol
 * The Ownable contract has 1 or 2 owner addresses, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract OwnableModified {
  address payable[] public owners;
  uint maxOwners;

  /**
    * Event emitted when a new owner has been added
    * @param addedOwner The new added owner of the contract.
    */
  event LogOwnerAdded(address payable indexed addedOwner);

  /**
    * Event emitted when ownership is tranferred
    * @param previousOwner The previous owner, who happened to effect the change.
    * @param newOwner The new, and current, owner of the contract.
    */
  event LogOwnershipTransferred(address payable indexed previousOwner, address indexed newOwner);

  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender
   * account.
   */
  constructor() public {
    owners.push(msg.sender);
    maxOwners = 2;
  }

  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    bool authorized = false;
    for (uint  i = 0; i < owners.length; i++) {
      if (msg.sender == owners[i]) {
        authorized = true;
      }
    }

    require(authorized);
    _;
  }

  /**
   * @dev Allows a current owner to add another address that can control of the contract.
   * @param newOwner The address to add ownership rights.
   */
  function addOwner(address payable newOwner)
    public
    onlyOwner
    returns (bool isSuccess)
  {
    require(owners.length < maxOwners);
    require(msg.sender != newOwner && newOwner != address(0));
    owners.push(newOwner);
    emit LogOwnerAdded(newOwner);

    return true;
  }

  function getOwnersLength() public view returns (uint) {
    return owners.length;
  }

  function getOwners() public view returns (address payable[] memory) {
    return owners;
  }

  /**
   * @dev Allows a current owner to transfer control of the contract to a newOwner.
   * @param newOwner The address to transfer ownership to.
   */
  function transferOwnership(address payable newOwner)
    public
    onlyOwner
    returns (bool isSuccess)
  {
    require(msg.sender != newOwner && newOwner != address(0));
    for (uint  i = 0; i < owners.length; i++) {
      if (msg.sender == owners[i]) {
        owners[i] = newOwner;
      }
    }
    emit LogOwnershipTransferred(msg.sender, newOwner);
    return true;
  }

}
