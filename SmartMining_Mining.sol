pragma solidity ^0.4.25;

import "github.com/oraclize/ethereum-api/oraclizeAPI_0.5.sol";

import "SafeMath.sol";


/**
 * @title Smart-Mining 'mining pool operation cost withdrawal'-contract - http://smart-mining.io - mail@smart-mining.io
 *
 * @dev Using http://oraclize.it to access ETHEUR exchange-ticker e.g. json(https://api.kraken.com/0/public/Ticker?pair=ETHEUR).result.XETHZEUR.c.0
 */
contract SmartMining_Mining is usingOraclize {
    using SafeMath for uint256;
    
    // -------------------------------------------------------------------------
    // Variables
    // -------------------------------------------------------------------------
    
    struct OraclizeQuery {                // 'OraclizeQuery'-struct
        bytes32 queryId;                  // Oraclize queries are asynchron, initiating a withdrawal will only return a queryId for the __callback
        uint256 ETHEUR;                   // The Oraclize __callback will return the current ETHEUR conversation price on exchange
        uint256 EUR;                      // The requested € (EUR) amount which will be send to WITHDRAWAL_ADDRESS for paying the operating costs
    }
    OraclizeQuery public withdrawal;      // The current requested and pending withdrawal as 'OraclizeQuery'-struct
    
    address public owner;                 // Owner of this contract
    uint256 public ORACLIZE_GAS_PRICE;    // The gas price used for the Oraclize __callback
    string  public ORACLIZE_QUERY;        // Oraclize URL query e.g. json(https://api.kraken.com/0/public/Ticker?pair=ETHEUR).result.XETHZEUR.c.0
    address public DISTRIBUTION_CONTRACT; // SmartMining 'crowdsale & profit distribution'-contract address
    address public WITHDRAWAL_ADDRESS;    // SmartMining controlled address which will trade received ETH against EUR for paying the operating costs
    
    
    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------
    
    constructor(address _owner) public {
        require(_owner != 0x0);
        
        // Initialize contract owner and trigger 'SetOwner'-event
        owner = _owner;
        emit SetOwner(owner);
        
        // Initialize Variables, for now we stay with kraken.com as our primary exchange.
        ORACLIZE_QUERY = "json(https://api.kraken.com/0/public/Ticker?pair=ETHEUR).result.XETHZEUR.c.0";
        emit Set_ORACLIZE_QUERY(ORACLIZE_QUERY);
        
        // Initalize Oraclize proof
        oraclize_setProof(proofType_TLSNotary | proofStorage_IPFS);
    }
    
    
    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------
    
    event SetOwner(address indexed newOwner);
    event Set_DISTRIBUTION_CONTRACT(address indexed DISTRIBUTION_CONTRACT);
    event Set_WITHDRAWAL_ADDRESS(address indexed WITHDRAWAL_ADDRESS);
    event Set_ORACLIZE_QUERY(string ORACLIZE_QUERY);
    event Set_ORACLIZE_GAS_PRICE(uint256 gasPrice);
    event InitiateWithdraw(uint256 operatingCost_EUR, uint256 gasLimit, uint256 gasPrice, bytes32 queryId, uint256 queryPrice);
    event DeletePendingWithdraw(bytes32 queryId);
    event Deposit(address indexed from, uint256 value);
    event WipeToContract(address indexed beneficiary, uint256 value);
    event OraclizeCallback(bytes32 queryId, string ETHEUR, bytes proof);
    event WithdrawOperatingCost(address indexed beneficiary, uint256 operatingCost_value, uint256 EUR, uint256 ETHEUR, bytes32 queryId);
    event WithdrawMiningProfit(address indexed beneficiary, uint256 miningProfit_value, bytes32 queryId);
    
    
    // -------------------------------------------------------------------------
    // OWNER ONLY external maintenance interface
    // -------------------------------------------------------------------------
    
    modifier onlyOwner () {
        require( msg.sender == owner );
        _;
    }
    
    function setOwner (address _newOwner) external onlyOwner {
        if( _newOwner != 0x0 ) {  owner = _newOwner; } else { owner = msg.sender; }
        emit SetOwner(owner);
    }
    
    function set_ORACLIZE_QUERY (string _ORACLIZE_QUERY) external onlyOwner {
        ORACLIZE_QUERY = _ORACLIZE_QUERY;
        emit Set_ORACLIZE_QUERY(ORACLIZE_QUERY);
    }
    
    function set_ORACLIZE_GAS_PRICE (uint256 _ORACLIZE_GAS_PRICE_gwei) external onlyOwner {
        ORACLIZE_GAS_PRICE = _ORACLIZE_GAS_PRICE_gwei.mul(10**9);
        emit Set_ORACLIZE_GAS_PRICE( ORACLIZE_GAS_PRICE );
        oraclize_setCustomGasPrice( ORACLIZE_GAS_PRICE );
    }
    
    function set_DISTRIBUTION_CONTRACT (address _DISTRIBUTION_CONTRACT) external onlyOwner {
        DISTRIBUTION_CONTRACT = _DISTRIBUTION_CONTRACT;
        emit Set_DISTRIBUTION_CONTRACT(DISTRIBUTION_CONTRACT);
    }
    
    function set_WITHDRAWAL_ADDRESS (address _WITHDRAWAL_ADDRESS) external onlyOwner {
        WITHDRAWAL_ADDRESS = _WITHDRAWAL_ADDRESS;
        emit Set_WITHDRAWAL_ADDRESS(WITHDRAWAL_ADDRESS);
    }
    
    function initiateWithdraw (uint256 _operatingCost_EUR, uint256 _gasLimit) external onlyOwner {
        // Precalculate the Oraclize query price, check if it cost under 800 Finney and contract hold enaugh funds
        uint256 oraclizeQueryPrice = oraclize_getPrice("URL", _gasLimit);
        require( oraclizeQueryPrice < address(this).balance && oraclizeQueryPrice < 800 finney );
        
        // Send the Oraclize query with gasLimit from parameter
        bytes32 queryId = oraclize_query("URL", ORACLIZE_QUERY, _gasLimit);
        emit InitiateWithdraw(_operatingCost_EUR, _gasLimit, ORACLIZE_GAS_PRICE, queryId, oraclizeQueryPrice);
        
        // Save the query data for the query __callback
        withdrawal = OraclizeQuery({
            queryId: queryId,
            ETHEUR: 0,
            EUR: _operatingCost_EUR
        });
    }
    
    function deletePendingWithdraw (bytes32 _queryId) external onlyOwner {
        require( _queryId == withdrawal.queryId );
        
        emit DeletePendingWithdraw(withdrawal.queryId);
        delete withdrawal;
    }
    
    // Fallback function, to send the whole Ether funds of this contract to the SmartMining 'crowdsale & profit distribution'-contract
    function wipeToContract () external onlyOwner {
        require( address(this).balance > 0 );
        require( DISTRIBUTION_CONTRACT != 0x0 );
        
        emit WipeToContract(DISTRIBUTION_CONTRACT, address(this).balance);
        require( DISTRIBUTION_CONTRACT.call.gas( gasleft() ).value( address(this).balance )() );
    }
    
    // -------------------------------------------------------------------------
    // Public external interface
    // -------------------------------------------------------------------------
    
    function () external payable {
        emit Deposit(msg.sender, msg.value);
    }
    
    function __callback(bytes32 _queryId, string _ETHEUR) public {
        __callback(_queryId, _ETHEUR, new bytes(0));
    }
    function __callback (bytes32 _queryId, string _ETHEUR, bytes proof) public {
        require( msg.sender == oraclize_cbAddress() );
        require( _queryId == withdrawal.queryId );
        require( WITHDRAWAL_ADDRESS != 0x0 && DISTRIBUTION_CONTRACT != 0x0 );
        emit OraclizeCallback(_queryId, _ETHEUR, proof);
        
        // Save the ETHEUR price what Oraclize told us as uint256 multiplied by 100 into query struct
        withdrawal.ETHEUR = parseInt(_ETHEUR, 2);
        
        // Calculate the needed ETH amount for the requested operating cost
        uint256 operatingCost = withdrawal.EUR.mul(10**20).div( withdrawal.ETHEUR );
        
        // Trigger Events for following transfers 
        emit WithdrawOperatingCost(WITHDRAWAL_ADDRESS, operatingCost, withdrawal.EUR, withdrawal.ETHEUR, _queryId);
        emit WithdrawMiningProfit(DISTRIBUTION_CONTRACT, address(this).balance, _queryId);
        
        // Delete this withdraw request
        delete withdrawal;
        
        // Transfer the operating cost to WITHDRAWAL_ADDRESS and the remaining mining profit to the DISTRIBUTION_CONTRACT
        // Contract call gas is unlimited to loop over all SmartMining member addresses on deposit
        WITHDRAWAL_ADDRESS.transfer( operatingCost );
        require( DISTRIBUTION_CONTRACT.call.gas( gasleft() ).value( address(this).balance )(bytes4(keccak256("deposit()"))) );
    }
    
    
}
