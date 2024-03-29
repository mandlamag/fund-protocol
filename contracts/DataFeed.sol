pragma solidity >=0.4.22 <0.6.0;

import './oraclize/oraclizeAPI_0.5.sol';
import './zeppelin/DestructibleModified.sol';
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "jsmnsol-lib/JsmnSolLib.sol";

contract IDataFeed {
    uint    public value;                  // Total portfolio value in USD
    uint    public usdEth;                 // USD/ETH exchange rate
}

contract DataFeed is usingOraclize, DestructibleModified {
    using SafeMath for uint;
    using JsmnSolLib for string;

    // Global variables
    bool    public useOraclize;            // True: use Oraclize.  False: use testRPC address.
    uint    public value;                  // Total portfolio value in USD
    uint    public usdUnsubscribedAmount;  // Total amount of USD in exchange account/NAV service not yet subscribed
    // to the fund.  When calculating NAV, this amount is to be excluded from
    // portfolio value
    uint    public usdEth;                 // USD/ETH exchange rate
    uint    public usdBtc;                 // USD/BTC exchange rate
    uint    public usdLtc;                 // USD/BTC exchange rate
    uint    public timestamp;              // Timestamp of last update

    // Oraclize-specific variables
    string  public queryUrl;               // URL of the API to query, usually "json(<URL>).XX"
    uint    public secondsBetweenQueries;  // Interval between queries
    mapping(bytes32 => bool) validIds;     // Array of queryIds that prevents duplicate queries
    uint    public gasLimit;
    uint    public gasPrice;

    // TestRPC-specific variables
    address public  exchange;              // Address of the exchange account used to calculate the value locally

    // Only emitted when useOraclize is true
    event LogDataFeedQuery(string description);
    event LogDataFeedResponse(string rawResult, uint value, uint usdEth, uint usdBtc, uint usdLtc, uint timestamp);
    event LogDataFeedError(string rawResult);
    event LogUsdUnsubscribedAmountUpdate(uint usdUnsubscribedAmount);
    event LogWithdrawal(address manager, uint eth);

    constructor(
        string  memory _queryUrl,
        uint _secondsBetweenQueries,
        uint _initialUsdEthRate,
        uint _initialUsdBtcRate,
        uint _initialUsdLtcRate,
        address _exchange
    )
    public
    payable
    {
        // Testing Oraclize using Ethereum bridge (see readme for more details)
        /** ### NOTE:  COMMENT THIS OUT FOR DEPLOYMENT / PRODUCTION ## **/
        OAR = OraclizeAddrResolverI(0x6f485C8BF6fc43eA212E93BBF8ce046C7f1cb475);

        // Constants
        queryUrl = _queryUrl;
        secondsBetweenQueries = _secondsBetweenQueries;
        exchange = _exchange;
        usdEth = _initialUsdEthRate;
        usdBtc = _initialUsdBtcRate;
        usdLtc = _initialUsdLtcRate;
        gasLimit = 300000;
        // Adjust this value depending on code length
        gasPrice = 50000000000;
        // 50 GWei, Oraclize default

        oraclize_setCustomGasPrice(gasPrice);
        oraclize_setProof(proofType_NONE);
    }

    // Updates the value variable by fetching the queryUrl via Oraclize.
    // Recursively calls the update function again after secondsBetweenQueries seconds
    function updateWithOraclize()
    public
    payable
    {
        if (useOraclize) {
            if (oraclize.getPrice("URL") > address(this).balance) {
                emit LogDataFeedQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
            } else {
                emit LogDataFeedQuery("Oraclize query was sent, standing by for the answer..");
                bytes32 queryId;
                if (secondsBetweenQueries > 0) {
                    queryId = oraclize_query(secondsBetweenQueries, "URL", queryUrl, gasLimit);
                } else {
                    queryId = oraclize_query("URL", queryUrl, gasLimit);
                }
                validIds[queryId] = true;
            }
        }
    }

    // Assumes that the result is a raw JSON object with at least 2 fields:
    // 1) portfolio value in ETH, with 2 decimal places
    // 2) current USD/ETH exchange rate, with 2 decimal places
    // The function parses the JSON and stores the value and usdEth.
    function __callback(bytes32 _myid, string memory _result) public {
        require(validIds[_myid], "Identifier must be in the list of valid IDs");
        require(msg.sender == oraclize_cbAddress(), "this action must be performed by oraclize address");
        uint returnValue;
        JsmnSolLib.Token[] memory tokens;
        uint actualNum;
        (returnValue, tokens, actualNum) = JsmnSolLib.parse(_result, 10);

        // Check for the success return code and that the object is not an error string
        if (returnValue == 0 && actualNum > 4) {
            string memory valueRaw = JsmnSolLib.getBytes(_result, tokens[2].start, tokens[2].end);
            uint unadjustedValue = parseInt(valueRaw, 2);
            require(unadjustedValue > usdUnsubscribedAmount, "UnadjustedValue must be more than unsubsribed amount");
            value = unadjustedValue.sub(usdUnsubscribedAmount);

            string memory usdEthRaw = JsmnSolLib.getBytes(_result, tokens[4].start, tokens[4].end);
            usdEth = parseInt(usdEthRaw, 2);

            string memory usdBtcRaw = JsmnSolLib.getBytes(_result, tokens[6].start, tokens[6].end);
            usdBtc = parseInt(usdBtcRaw, 2);

            string memory usdLtcRaw = JsmnSolLib.getBytes(_result, tokens[8].start, tokens[8].end);
            usdLtc = parseInt(usdLtcRaw, 2);

            timestamp = block.number * 14;

            emit LogDataFeedResponse(_result, value, usdEth, usdBtc, usdLtc, timestamp);
            if (secondsBetweenQueries > 0) {
                updateWithOraclize();
            }
        } else {
            emit LogDataFeedError(_result);
        }
        delete validIds[_myid];
    }

    function updateWithExchange(uint _percent) public
    onlyOwner
    returns (bool success)
    {
        if (!useOraclize) {
            value = exchange.balance.mul(usdEth).mul(_percent).div(1e20).sub(usdUnsubscribedAmount);
            timestamp = block.number * 14;
            emit LogDataFeedResponse("mock", value, usdEth, usdBtc, usdLtc, timestamp);
            return true;
        }
    }

    // Manager override of values
    // Amounts are in units of 1 cent, i.e. $123.45 corresponds to an input if 12345
    function updateByManager(uint _portfolioValue, uint _usdEth, uint _usdBtc, uint _usdLtc) public
    onlyOwner
    returns (bool success)
    {
        require(_portfolioValue > 0 && _usdEth > 0 && _usdBtc > 0 && _usdLtc > 0, "Amounts must greater than 0");
        value = _portfolioValue;
        usdEth = _usdEth;
        usdBtc = _usdBtc;
        usdLtc = _usdLtc;
        timestamp = block.number * 14;
        emit LogDataFeedResponse("manager update", value, usdEth, usdBtc, usdLtc, timestamp);
        return true;
    }

    // Amounts are in units of 1 cent, i.e. $123.45 corresponds to an input if 12345
    function updateUsdUnsubscribedAmount(uint _usdUnsubcribedAmount)
    public
    onlyOwner
    returns (bool success)
    {
        require(_usdUnsubcribedAmount >= 0, "Unsubscribed amounts cannot be less than 0");
        usdUnsubscribedAmount = _usdUnsubcribedAmount;
        emit LogUsdUnsubscribedAmountUpdate(usdUnsubscribedAmount);
        return true;
    }

    // ********* ADMIN *********

    function changeQueryUrl(string memory _url)
    public
    onlyOwner
    returns (bool success)
    {
        queryUrl = _url;
        return true;
    }

    function changeInterval(uint _seconds)
    public
    onlyOwner
    returns (bool success)
    {
        secondsBetweenQueries = _seconds;
        return true;
    }

    function changeGasPrice(uint _price)
    public
    onlyOwner
    returns (bool success)
    {
        gasPrice = _price;
        oraclize_setCustomGasPrice(_price);
        return true;

    }

    function changeGasLimit(uint _limit)
    public
    onlyOwner
    returns (bool success)
    {
        gasLimit = _limit;
        return true;
    }

    function toggleUseOraclize()
    public
    onlyOwner
    returns (bool)
    {
        useOraclize = !useOraclize;
        return useOraclize;
    }

    function withdrawBalance()
    public
    onlyOwner
    returns (bool success)
    {
        uint payment = address(this).balance;
        msg.sender.transfer(payment);
        emit LogWithdrawal(msg.sender, payment);
        return true;
    }

}