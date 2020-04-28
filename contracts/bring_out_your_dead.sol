pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

// Alfred.Estate - Proof of Death - Digital Inheritance Automation

import "SafeMath.sol";
import "IERC20.sol";

import "https://github.com/gnosis/safe-contracts/blob/v1.1.1/contracts/base/Module.sol";
import "https://github.com/gnosis/safe-contracts/blob/v1.1.1/contracts/base/ModuleManager.sol";
import "https://github.com/gnosis/safe-contracts/blob/v1.1.1/contracts/base/OwnerManager.sol";
import "https://github.com/gnosis/safe-contracts/blob/v1.1.1/contracts/common/Enum.sol";


contract BringOutYourDead is Module {
    uint constant MAX_UINT = 2**256 - 1;
    address constant KYBER_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public KYBER_NETWORK_PROXY_ADDRESS = 0x818E6FECD516Ecc3849DAf6845e3EC868087B755;
    address constant REFERAL_ADDRESS = 0xdac3794d1644D7cE73d098C19f33E7e10271b2bC;
    
    address public owner;
    address public gnosisSafe;
    address public executor;
    address public oracle;
    address[] public beneficiaries;
    mapping(address => uint256) public beneficiaryShares;
    mapping(address => uint256) public beneficiaryIndex;
    mapping(address => mapping(address => bool)) public isBeneficiaryTokenWithdrawn;
    mapping(address => uint256) public totalTokensKnown;
    uint256 public totalShares;
    // TODO: Further evaluate if precision is sufficient for share ratios
    uint256 private precision = 8**10;
    address[] public trackedTokens;
    
    enum Lifesigns { Alive, Dead, Uncertain }
    Lifesigns public liveliness;
    uint256 public declareDeadAfter;
    uint256 public uncertaintyPeriod = 8 weeks;
    // uint256 public uncertaintyPeriod = 8 seconds;  // For demonstration

    // Gnosis Safe Recovery settings
    bool public isExecutorRequiredForSafeRecovery;
    uint256 public beneficiariesRequiredForSafeRecovery;
    // isExecuted mapping maps data hash to execution status.
    mapping (bytes32 => bool) public isExecuted;
    // isConfirmed mapping maps data hash to beneficiary's address to confirmation status.
    mapping (bytes32 => mapping (address => bool)) public isConfirmed;

    // Dead Man's Switch settings
    bool public isDeadMansSwitchEnabled;
    uint256 public deadMansSwitchCheckinSeconds;
    uint256 public deadMansSwitchLastCheckin;

    struct ShareHolder {
        address who;
        uint256 shares;
    }

    event ReportOfDeath(address indexed reporter);
    event ConfirmationOfLife(address indexed reporter);
    event ConfirmationOfDeath();
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event GnosisSafeChanged(address indexed gnosisSafe, address indexed newSafe);
    event OracleChanged(address indexed oldOracle, address indexed newOracle);
    event ExecutorChanged(address indexed oldExecutor, address indexed newExecutor);
    event AddedBeneficiary(address indexed newBeneficiary, uint256 indexed shares);
    event RemovedBeneficiary(address indexed formerBeneficiary, uint256 indexed removedShares);
    event ChangedBeneficiaryShares(address indexed beneficiary, uint256 indexed oldShares, uint256 indexed newShares);
    event ChangedBeneficiaryAddress(address indexed oldAddress, address indexed newAddress);
    event BeneficiaryWithdrawal(address indexed beneficiary, address indexed token, uint256 indexed amount);
    event TrackedTokenAdded(address indexed token);
    event TrackedTokenRemoved(address indexed token);
    event IsExecutorRequiredForSafeRecoveryChanged(bool indexed newValue);
    event BeneficiariesRequiredForSafeRecoveryChanged(uint256 indexed newValue);
    event IsDeadMansSwitchEnabledChanged(bool indexed newValue);
    event DeadMansSwitchCheckinSecondsChanged(uint256 indexed newValue);
    // event DeadMansSwitchCheckin();

    // TODO: Ability for owner to invest/withdraw from interest bearing savings contracts
    // TODO: Add second waiting period after death for executor to withdraw and pay debts before payout to beneficiaries
    // TODO: Support withdrawal/settling from loan dapps prior to any withdrawals
    // TODO: After second waiting period establish actual share per beneficiary based on share proportions

    
    modifier onlyOwner() {
        require(msg.sender == owner || msg.sender == gnosisSafe, "Caller is not the owner");
        require(liveliness != Lifesigns.Dead, "Owner is no longer alive");
        _;
    }
    
    modifier onlyExecutor() {
        require(msg.sender == executor, "Caller is not the executor");
        _;
    }
    
    modifier onlyOwnerOrExecutor() {
        require(msg.sender == owner || msg.sender == gnosisSafe || msg.sender == executor, "Caller is not the owner or executor");
        _;
    }
    
    modifier onlyController() {
        if(liveliness != Lifesigns.Dead) {
            require(msg.sender == owner || msg.sender == gnosisSafe, "Caller is not the owner and the owner is still alive");
        } else {
            require(msg.sender == executor, "Caller is not the executor and the owner is no longer alive");
        }
        _;
    }
    
    modifier onlyControllerOrBeneficiary(address who) {
        if(msg.sender != who) {
            if(liveliness != Lifesigns.Dead) {
                require(msg.sender == owner || msg.sender == gnosisSafe, "Caller is not the beneficiary or the owner and the owner is still alive");
            } else {
                require(msg.sender == executor, "Caller is not the beneficiary or the executor and the owner is no longer alive");
            }
        }
        _;
    }

    modifier onlyBeneficiary() {
        require(beneficiaryShares[msg.sender] > 0, "Caller does not have any shares");
        _;
    }

    modifier onlyMember() {
        require(msg.sender == owner || msg.sender == gnosisSafe || msg.sender == executor || beneficiaryShares[msg.sender] > 0, "Caller is not a member");
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == oracle, "Caller is not the oracle");
        _;
    }

    modifier notDead() {
        require(liveliness != Lifesigns.Dead, "Owner is no longer alive");
        _;
    }
    
    modifier onlyDead() {
        require(liveliness == Lifesigns.Dead, "Owner is not yet confirmed dead");
        _;
    }
    
    constructor() public {
        owner = msg.sender;
        liveliness = Lifesigns.Alive;
        isExecutorRequiredForSafeRecovery = true;
        beneficiariesRequiredForSafeRecovery = 1;
    }
    
    function () external payable {
    }
    
    /// @dev Allows an executor or beneficiary to confirm a Safe transaction.
    /// @param dataHash Safe transaction hash.
    function confirmTransaction(bytes32 dataHash)
        public
        onlyMember
    {
        require(!isExecuted[dataHash], "Recovery already executed");
        isConfirmed[dataHash][msg.sender] = true;
    }
    
    /// @dev Returns if Safe transaction is a valid owner replacement transaction.
    /// @param prevOwner Owner that pointed to the owner to be replaced in the linked list
    /// @param oldOwner Owner address to be replaced.
    /// @param newOwner New owner address.
    /// @return Returns if transaction can be executed.
    function recoverAccess(address prevOwner, address oldOwner, address newOwner)
        public
        onlyMember
    {
        bytes memory data = abi.encodeWithSignature("swapOwner(address,address,address)", prevOwner, oldOwner, newOwner);
        bytes32 dataHash = getDataHash(data);
        require(!isExecuted[dataHash], "Recovery already executed");
        require(isConfirmedByRequiredParties(dataHash), "Recovery has not enough confirmations");
        isExecuted[dataHash] = true;
        require(manager.execTransactionFromModule(address(manager), 0, data, Enum.Operation.Call), "Could not execute recovery");
    }
    
    /// @dev Returns if Safe transaction is a valid owner replacement transaction.
    /// @param dataHash Data hash.
    /// @return Confirmation status.
    function isConfirmedByRequiredParties(bytes32 dataHash)
        public
        view
        returns (bool)
    {
        if(isExecutorRequiredForSafeRecovery && !isConfirmed[dataHash][executor]) {
            return false;
        }
        if(beneficiariesRequiredForSafeRecovery > 0 && beneficiaries.length > 0) {
            uint256 confirmationCount;
            for (uint256 i = 0; i < beneficiaries.length; i++) {
                if (isConfirmed[dataHash][beneficiaries[i]]) {
                    confirmationCount++;
                }
                if (confirmationCount == beneficiariesRequiredForSafeRecovery) {
                    return true;
                }
            }
            
        }
        return false;
    }
    
    /// @dev Returns hash of data encoding owner replacement.
    /// @param data Data payload.
    /// @return Data hash.
    function getDataHash(bytes memory data)
        public
        pure
        returns (bytes32)
    {
        return keccak256(data);
    }
    
    // The Gnosis Safe creating this estate should call this function during initialization
    function gnosisSafeSetup() public onlyOwner {
        // Gnosis Safe contracts/base/Module.sol:
        setManager();
        setGnosisSafe(msg.sender);
    }
    
    // The Gnosis Safe associated with this contract acts as a co-owner and has the full rights that the primary owner has
    function setGnosisSafe(address newSafe) public onlyOwner {
        // Allow setting to zero address to disable Gnosis Safe co-ownership
        // require(newSafe != address(0), "Gnosis Safe address is missing");
        emit GnosisSafeChanged(gnosisSafe, newSafe);
        gnosisSafe = newSafe;
    }
    
    function setIsExecutorRequiredForSafeRecovery(bool newValue) public onlyOwner {
        emit IsExecutorRequiredForSafeRecoveryChanged(newValue);
        isExecutorRequiredForSafeRecovery = newValue;
    }
    
    function setBeneficiariesRequiredForSafeRecovery(uint256 newValue) public onlyOwner {
        emit BeneficiariesRequiredForSafeRecoveryChanged(newValue);
        beneficiariesRequiredForSafeRecovery = newValue;
    }
    
    function setIsDeadMansSwitchEnabled(bool newValue) public onlyOwner {
        emit IsDeadMansSwitchEnabledChanged(newValue);
        isDeadMansSwitchEnabled = newValue;
        if(true == newValue) {
            deadMansSwitchLastCheckin = now;
        }
    }
    
    function setDeadMansSwitchCheckinSeconds(uint256 newValue) public onlyOwner {
        require(0 != newValue, "Dead Man's Switch check-in seconds must be greater than zero");
        emit DeadMansSwitchCheckinSecondsChanged(newValue);
        deadMansSwitchCheckinSeconds = newValue;
    }
    
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner is missing");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
    
    function changeOracle(address newOracle) public onlyOwner {
        require(newOracle != address(0), "New oracle is missing");
        emit OracleChanged(oracle, newOracle);
        oracle = newOracle;
    }
    
    function changeExecutor(address newExecutor) public onlyOwnerOrExecutor {
        require(newExecutor != address(0), "New executor is missing");
        emit ExecutorChanged(executor, newExecutor);
        executor = newExecutor;
    }

    function getBeneficiariesDetails() public view returns (ShareHolder[] memory beneficiaryDetails) {
        for(uint i=0; i<beneficiaries.length; i++) {
            beneficiaryDetails[i] = ShareHolder(beneficiaries[i], beneficiaryShares[beneficiaries[i]]);
        }
    }
    
    // Determine size of beneficiaries share of tokens given locked in or current balance
    function getBeneficiaryBalance(address beneficiary, address token) public view returns (uint256 shareBalance) {
        // Check if tokens have already been balanced
        if(isBeneficiaryTokenWithdrawn[beneficiary][token]) {
            return 0;
        }
        // Determine the total amount of ETH or tokens held if not yet known, but don't lock total in permanently
        uint totalTokens;
        if(totalTokensKnown[token] > 0) {
            totalTokens = totalTokensKnown[token];
        } else {
            if(address(0) == token) {
                totalTokens = address(this).balance;
            } else {
                totalTokens = IERC20(token).balanceOf(address(this));
            }
        }

        uint256 shareRatio = SafeMath.div(SafeMath.mul(precision, totalShares), beneficiaryShares[beneficiary]);
        uint256 share = SafeMath.div(SafeMath.mul(precision, totalTokens), shareRatio);

        return share;

    }

    function addBeneficiary(address newBeneficiary, uint256 shares) public onlyController {
        require(newBeneficiary != address(0), "New beneficiary is missing");
        require(shares > 0, "Shares must be greater than zero");
        require(beneficiaryShares[newBeneficiary] == 0, "New beneficiary already exists");
        uint256 index = beneficiaries.push(newBeneficiary);
        beneficiaryIndex[newBeneficiary] = index;
        beneficiaryShares[newBeneficiary] = shares;
        totalShares = SafeMath.add(totalShares, shares);
        emit AddedBeneficiary(newBeneficiary, shares);
    }
    
    function removeBeneficiary(address beneficiary) public onlyController {
        require(beneficiary != address(0), "Beneficiary address is missing");
        require(beneficiaryShares[beneficiary] > 0, "Account is not a current beneficiary");
        uint256 index = beneficiaryIndex[beneficiary];
        for(uint256 i = index; i<beneficiaries.length; i++) {
            beneficiaries[i] = beneficiaries[i+1];
        }
        beneficiaries.length = beneficiaries.length-1;
        beneficiaryIndex[beneficiary] = 0;
        beneficiaryShares[beneficiary] = 0;
        uint256 sharesRemoved = beneficiaryShares[beneficiary];
        totalShares = SafeMath.sub(totalShares, sharesRemoved);
        emit RemovedBeneficiary(beneficiary, sharesRemoved);
    }

    function changeBeneficiaryShares(address beneficiary, uint256 newShares) public onlyController {
        require(beneficiary != address(0), "Beneficiary address is missing");
        require(beneficiaryShares[beneficiary] > 0, "Account is not a current beneficiary");
        // require(newShares > 0, "Shares must be greater than zero");
        uint256 oldShares = beneficiaryShares[beneficiary];
        totalShares = SafeMath.sub(totalShares, oldShares);
        totalShares = SafeMath.add(totalShares, newShares);
        beneficiaryShares[beneficiary] = newShares;
        emit ChangedBeneficiaryShares(beneficiary, oldShares, newShares);
    }
    
    function changeBeneficiaryAddress(address oldAddress, address newAddress) public onlyControllerOrBeneficiary(oldAddress) {
        require(oldAddress != address(0), "Old beneficiary address is missing");
        require(newAddress != address(0), "New beneficiary address is missing");
        // require(beneficiaryShares[oldAddress] > 0, "Account is not a current beneficiary");
        uint256 index = beneficiaryIndex[oldAddress];
        uint256 shares = beneficiaryShares[oldAddress];
        beneficiaries[index] = newAddress;
        beneficiaryShares[oldAddress] = 0;
        beneficiaryShares[newAddress] = shares;
        emit ChangedBeneficiaryAddress(oldAddress, newAddress);
    }
    
    function claimEthShares() public {
        claimTokenShares(address(0));
    }

    function claimTokenShares(address token) public onlyDead onlyBeneficiary {
        determinePoolSize(token);
        sendShare(msg.sender, token, token);
    }

    function claimTokenSharesAsEth(address token) public onlyDead onlyBeneficiary {
        determinePoolSize(token);
        sendShare(msg.sender, token, address(0));
    }
    
    function distributeEthShares() public {
        distributeTokenShares(address(0));
    }

    function distributeTokenShares(address token) public onlyDead onlyExecutor {
        determinePoolSize(token);
        for(uint256 i=0; i < beneficiaries.length; i++) {
            address payable b = address(uint160(beneficiaries[i]));
            sendShare(b, token, token);
        }
    }

    function distributeTokenSharesAsEth(address token) public onlyDead onlyExecutor {
        determinePoolSize(token);
        for(uint256 i=0; i < beneficiaries.length; i++) {
            address payable b = address(uint160(beneficiaries[i]));
            sendShare(b, token, address(0));
        }
    }
    
    function determinePoolSize(address token) internal {
        // Determine the total amount of ETH or tokens held if not yet known
        if(totalTokensKnown[token] == 0) {
            if(address(0) == token) {
                totalTokensKnown[token] = address(this).balance;
            } else {
                totalTokensKnown[token] = IERC20(token).balanceOf(address(this));
            }
        }
    }
    
    function sendShare(address payable beneficiary, address token, address receiveToken) internal {
        if(!isBeneficiaryTokenWithdrawn[beneficiary][token]) {
            // TODO: Extensive testing of these operations for edge cases and rounding issues:
            uint256 shareRatio = SafeMath.div(SafeMath.mul(precision, totalShares), beneficiaryShares[beneficiary]);
            uint256 share = SafeMath.div(SafeMath.mul(precision, totalTokensKnown[token]), shareRatio);
            isBeneficiaryTokenWithdrawn[beneficiary][token] = true;
            if(address(0) == token) {
                require(beneficiary.send(share), "Problem sending share");
            } else {
                if(receiveToken != token) {
                    if(address(0) == receiveToken) {
                        receiveToken = KYBER_ETH_ADDRESS;
                    }
                    // Convert to desired token or ETH through Kyber
                    IERC20(token).approve(KYBER_NETWORK_PROXY_ADDRESS, 0);
                    IERC20(token).approve(KYBER_NETWORK_PROXY_ADDRESS, MAX_UINT);
                    uint256 min_conversion_rate;
                    uint256 result;
                    (min_conversion_rate,) = KyberNetworkProxy(KYBER_NETWORK_PROXY_ADDRESS).getExpectedRate(token, receiveToken, share);
                    result = KyberNetworkProxy(KYBER_NETWORK_PROXY_ADDRESS).tradeWithHint(token, share, receiveToken, beneficiary, MAX_UINT, min_conversion_rate, REFERAL_ADDRESS, '');
                    require(result > 0, "Failed to convert token through Kyber");
                } else {
                    // Don't require token transfer to succeed, since some tokens don't follow spec.
                    // TODO: Could use OpenZepelin SafeERC20 to guarantee transfer succeeded
                    IERC20(token).transfer(beneficiary, share);
                }
            }
            emit BeneficiaryWithdrawal(beneficiary, token, share);
        }
    }
    
    function addTrackedToken(address token) public onlyController {
        require(address(0) != token, "Token address is missing");
        emit TrackedTokenAdded(token);
        trackedTokens.push(token);
    }
    
    function removeTrackedToken(address token) public onlyController {
        require(address(0) != token, "Token address is missing");
        uint256 index;
        emit TrackedTokenRemoved(token);
        // TODO: finish this
        uint256 i;
        for(i=0; i<trackedTokens.length; i++) {
            if(trackedTokens[i] == token) {
                index = i;
                break;
            }
        }
        if(index < trackedTokens.length-1) {
            trackedTokens[i] = trackedTokens[trackedTokens.length-1];
        }
        trackedTokens.length--;
    }

    
    function oracleCallback(bool isDead) public onlyOracle notDead {
        if(isDead) {
            setUncertain();
        }
        //else {
        //    setAlive();
        //}
    }

    // With dead man's switch: Call after the check-in period has passed without the owner checking in
    // With death oracle: Call after owner has been reported dead and the waiting period has passed to establish confirmation of death
    function bringOutYourDead() public onlyMember {
        setDead();
    }

    function imNotDeadYet() public onlyOwner {
        setAlive();
    }
    
    function sendEth(address payable recipient, uint256 amount) public onlyOwner {
        recipient.send(amount);
    }
    
    function sendToken(address payable recipient, address token, uint256 amount) public onlyOwner {
        IERC20(token).transfer(recipient, amount);
    }
    
    /*
    function execute(address target, uint256 amount, bytes data) {
    }
    */

    function setAlive() internal notDead {
        emit ConfirmationOfLife(msg.sender);
        liveliness = Lifesigns.Alive;
        declareDeadAfter = 0;
        if(isDeadMansSwitchEnabled) {
            deadMansSwitchLastCheckin = now;
        }
    }

    function setUncertain() internal notDead {
            emit ReportOfDeath(msg.sender);
            liveliness = Lifesigns.Uncertain;
            declareDeadAfter = now + uncertaintyPeriod;
    }

    function setDead() internal notDead {
        // NOTE: This functionality will be enabled when the death oracle is fully implemented
        // require(liveliness == Lifesigns.Uncertain, "Owner has not been reported as dead yet");
        // require(declareDeadAfter != 0 && declareDeadAfter < now, "Owner still has time to demonstrate life");

        require(isDeadMansSwitchEnabled, "Dead Man's Switch is not enabled");
        require(deadMansSwitchLastCheckin + (deadMansSwitchCheckinSeconds) < now, "Owner has checked-in as alive too recently");
        emit ConfirmationOfDeath();
        liveliness = Lifesigns.Dead;
    }
    
}

contract KyberNetworkProxy {
  function removeAlerter ( address alerter ) external;
  function enabled (  ) external view returns ( bool );
  function pendingAdmin (  ) external view returns ( address );
  function getOperators (  ) external view returns ( address[] memory );
  function tradeWithHint ( address src, uint256 srcAmount, address dest, address destAddress, uint256 maxDestAmount, uint256 minConversionRate, address walletId, bytes calldata hint ) external payable returns ( uint256 );
  function swapTokenToEther ( address token, uint256 srcAmount, uint256 minConversionRate ) external returns ( uint256 );
  function withdrawToken ( address token, uint256 amount, address sendTo ) external;
  function maxGasPrice (  ) external view returns ( uint256 );
  function addAlerter ( address newAlerter ) external;
  function kyberNetworkContract (  ) external view returns ( address );
  function getUserCapInWei ( address user ) external view returns ( uint256 );
  function swapTokenToToken ( address src, uint256 srcAmount, address dest, uint256 minConversionRate ) external returns ( uint256 );
  function transferAdmin ( address newAdmin ) external;
  function claimAdmin (  ) external;
  function swapEtherToToken ( address token, uint256 minConversionRate ) external payable returns ( uint256 );
  function transferAdminQuickly ( address newAdmin ) external;
  function getAlerters (  ) external view returns ( address[] memory );
  function getExpectedRate ( address src, address dest, uint256 srcQty ) external view returns ( uint256 expectedRate, uint256 slippageRate );
  function getUserCapInTokenWei ( address user, address token ) external view returns ( uint256 );
  function addOperator ( address newOperator ) external;
  function setKyberNetworkContract ( address _kyberNetworkContract ) external;
  function removeOperator ( address operator ) external;
  function info ( bytes32 field ) external view returns ( uint256 );
  function trade ( address src, uint256 srcAmount, address dest, address destAddress, uint256 maxDestAmount, uint256 minConversionRate, address walletId ) external payable returns ( uint256 );
  function withdrawEther ( uint256 amount, address sendTo ) external;
  function getBalance ( address token, address user ) external view returns ( uint256 );
  function admin (  ) external view returns ( address );
}
