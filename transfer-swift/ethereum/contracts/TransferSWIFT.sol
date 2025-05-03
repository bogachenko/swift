// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// @openzeppelin/contracts: Import libraries
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

/// @title TransferSWIFT
/// @author Bogachenko Vyacheslav
/// @notice TransferSWIFT is a universal contract for batch transfers of native coins and tokens.
/// @custom:licence License: MIT
/// @custom:version Version 0.0.0.7 (stable)

contract TransferSWIFT is AccessControlEnumerable, ReentrancyGuard, Pausable {
    /*********************************************************************/
    /// @title Contract configuration and state parameters
    /// @notice This section contains contract state variables and settings
    /*********************************************************************/
    /// @notice Administrator role hash
    /// @dev Grants full access to contract management
    /// @dev Should be granted cautiously
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Moderator role hash
    /// @dev Grants access to moderation functions
    /// @dev Should be granted cautiously
    bytes32 public constant MOD_ROLE = keccak256("MOD_ROLE");
    /// @notice User role hash
    /// @dev Base access level for standard users
    bytes32 public constant USER_ROLE = keccak256("USER_ROLE");
    /// @notice Maximum administrator count
    uint256 public constant MAX_ADMINS = 3;
    /// @notice Maximum moderator count
    uint256 public constant MAX_MODS = 10;
    /// @notice Data for the current royalty withdrawal request
    /// @dev Stores pending request details (address, amount, timestamp)
    WithdrawalRequest public withdrawalRequest;
    /// @notice Royalty withdrawal cooldown period
    /// @dev Security delay of 3 days (3 * 86400 seconds)
    uint256 public constant withdrawalDelay = 259200 seconds;
    /// @notice Address library for safe ETH operations
    using Address for address payable;
    /// @notice SafeERC20 library for safe ERC-20 operations
    using SafeERC20 for IERC20;
    /// @notice Contract owner address
    address public owner;
    /// @notice Address data of the candidate for ownership
    /// @dev Used for two-step ownership transfer
    address public pendingOwner;
    /// @notice Protocol display name
    /// @dev Used for interface identification
    string public name = "TransferSWIFT";
    /// @notice Protocol symbol
    /// @dev Used for interface identification
    string public symbol = "SWIFT";
    /// @notice Contract transaction fee
    /// @dev Default value: 0.000001 ETH (1e12 wei)
    /// @dev Must be in range [minTaxFee, maxTaxFee]
    uint256 public taxFee = 1e12;
    /// @notice Minimum allowed contract fee
    /// @dev Value: 0.00000001 ETH (1e10 wei)
    uint256 public minTaxFee = 1e10;
    /// @notice Maximum allowed contract fee
    /// @dev Value: 0.0005 ETH (5e14 wei)
    uint256 public maxTaxFee = 5e14;
    /// @notice Accumulated protocol royalties
    /// @dev Total collected fees awaiting distribution
    uint256 public accumulatedRoyalties;
    /// @notice Default recipient limit
    /// @dev Default allowance: 15 recipients
    uint256 constant defaultRecipients = 15;
    /// @notice Maximum recipient limit
    /// @dev Absolute maximum: 20 recipients
    uint256 constant maxRecipients = 20;
    /// @notice Rate limiting duration
    /// @dev Default value: 300 seconds (5 minutes)
    uint256 public rateLimitDuration = 300;
    /// @notice Contract emergency stop flag
    /// @dev Blocking the main functions of the contract
    bool public isEmergencyStopped;
    /// @dev Maintaining a pause state before emergency activation
    bool private _wasPausedBeforeEmergency;
    /// @notice Emergency activation reason
    /// @dev Saving a hashed message describing the reason
    bytes32 public emergencyReason;
    /// @notice Limit of failed transfers to automatically activate the emergency stop
    /// @dev Only for the owner of the contract
    uint256 public constant maxFailedTransfers = 3;

    /*********************************************************************/
    /// @title Contract access control and restrictions
    /// @notice This section contains permission mappings and usage restrictions
    /*********************************************************************/
    /// @notice Last used timestamp data
    /// @dev Stores block timestamps for address-based cooldown tracking
    /// @return timestamp - Last interaction time (UNIX format)
    mapping(address => uint256) public lastUsed;
    /// @notice List of banned addresses
    /// @dev Blocked addresses cannot interact with main functions
    /// @return status - True if address is blacklisted
    mapping(address => bool) public blacklist;
    /// @notice List of extended recipient addresses
    /// @dev Addresses with enlarged recipient limits
    /// @return hasExtendedLimit - True if extended limit is granted
    mapping(address => bool) public extendedRecipients;
    /// @notice Allowed ERC20 tokens for operations
    /// @dev Token contract addresses permitted for transactions
    /// @return isWhitelisted - True if token is approved
    mapping(address => bool) public whitelistERC20;
    /// @notice Allowed ERC721 tokens for operations
    /// @dev Token contract addresses permitted for transactions
    /// @return isWhitelisted - True if token is approved
    mapping(address => bool) public whitelistERC721;
    /// @notice Allowed ERC1155 tokens for operations
    /// @dev Token contract addresses permitted for transactions
    /// @return isWhitelisted - True if token is approved
    mapping(address => bool) public whitelistERC1155;

    /*********************************************************************/
    /// @title Contains data structures for handling contract requests
    /// @notice Implements security measures using templates
    /*********************************************************************/
    /// @notice Royalty Withdrawal Request Structure
    /// @dev Represents a pending royalty withdrawal request
    /// @dev Enforces security cooldown period before withdrawal execution
    /// @param amount - Requested withdrawal amount in wei
    /// @param requestTime - Timestamp of request creation (UNIX format)
    /// @param isCancelled - Flag to mark request as cancelled (true = inactive)
    /// @param isRoyalties - Flag to differentiate royalty withdrawals from ETH withdrawals (true = royalty)
    struct WithdrawalRequest {
        uint256 amount;
        uint256 requestTime;
        bool isCancelled;
        bool isRoyalties;
    }

    /*********************************************************************/
    /// @title Contract Lifecycle Events
    /// @notice Events related to contract configuration changes
    /*********************************************************************/
    /// @notice Emitted when ownership transfer is completed
    /// @dev Logs both previous and new contract owners
    /// @param previousOwner - Address of the outgoing owner
    /// @param newOwner - Address of the new owner
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    /// @notice Emitted when ownership transfer is initiated
    /// @dev Marks the beginning of a two-step ownership transfer process
    /// @param currentOwner - Address of the current owner
    /// @param pendingOwner - Address of the pending new owner
    event OwnershipTransferInitiated(
        address indexed currentOwner,
        address indexed pendingOwner
    );
    /// @notice Emitted when ownership is permanently renounced
    /// @dev Indicates contract has become ownerless
    /// @param previousOwner - Address of the last owner
    event OwnershipRenounced(address indexed previousOwner);
    /// @notice Emitted when emergency stop is activated
    /// @dev Freezes critical contract functionality
    /// @param executor - Address that triggered the emergency stop
    /// @param reason - Hash of the reason description (Bytes32 format)
    event EmergencyStopActivated(address indexed executor, bytes32 reason);
    /// @notice Emitted when emergency stop is deactivated
    /// @dev Restores normal contract operations
    /// @param executor - Address that lifted the emergency stop
    event EmergencyStopLifted(address indexed executor);
    /// @notice Emitted when ETH withdrawal is initiated
    /// @dev Marks the start of withdrawal delay period
    /// @param amount - Requested amount in wei
    /// @param requestTime - Timestamp of request creation
    event WithdrawalRequested(uint256 amount, uint256 requestTime);
    /// @notice Emitted when withdrawal is canceled
    /// @dev Resets pending withdrawal request
    event WithdrawalCancelled();
    /// @notice Emitted when withdrawal is completed
    /// @dev Confirms successful funds transfer
    /// @param amount - Transferred amount in wei
    event WithdrawalCompleted(uint256 amount);
    /// @notice Emitted when recipient limit is increased
    /// @dev Overrides `defaultRecipients` for specific address
    /// @param user - Address receiving limit extension
    /// @param limit - New maximum recipient allowance
    event MaxRecipientsSet(address indexed user, uint256 limit);
    /// @notice Emitted when recipient limit is reset
    /// @dev Restores `defaultRecipients` value for address
    /// @param user - Address affected by reset
    /// @param limit - Standard recipient allowance
    event DefaultRecipientsSet(address indexed user, uint256 limit);
    /// @notice Emitted when blacklist status changes
    /// @dev Affects access to contract functionality
    /// @param user - Modified address
    /// @param status - New status (true = blacklisted)
    event BlacklistUpdated(address indexed user, bool status);
    /// @notice Emitted when ERC20 token is whitelisted
    /// @dev Controls allowed tokens for operations
    /// @param token - ERC20 contract address
    /// @param status - New status (true = allowed)
    event WhitelistERC20Updated(address indexed token, bool status);
    /// @notice Emitted when ERC721 token is whitelisted
    /// @dev Controls allowed tokens for operations
    /// @param token - ERC721 contract address
    /// @param status - New status (true = allowed)
    event WhitelistERC721Updated(address indexed token, bool status);
    /// @notice Emitted when ERC1155 token is whitelisted
    /// @dev Controls allowed tokens for operations
    /// @param token - ERC1155 contract address
    /// @param status - New status (true = allowed)
    event WhitelistERC1155Updated(address indexed token, bool status);

    /*********************************************************************/
    /// @title Access Control Modifiers
    /// @notice Modifiers for checking permissions
    /*********************************************************************/
    /// @notice Restricts function to contract owner only
    /// @dev Verifies `msg.sender` matches stored owner address
    /// @dev Throws if called by any account other than the owner.
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    /// @notice Restricts access to admin role holders
    /// @dev Admins have highest privilege level
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Not admin");
        _;
    }
    /// @notice Restricts access to moderator role holders
    /// @dev Moderators have elevated privileges for content management
    modifier onlyMod() {
        require(hasRole(MOD_ROLE, msg.sender), "Not mod");
        _;
    }
    /// @notice Restricts access to user role holders
    /// @dev Base access level for registered users
    modifier onlyUser() {
        require(hasRole(USER_ROLE, msg.sender), "Not user");
        _;
    }
    /// @notice Blacklist access control
    /// @dev Prevents access for blacklisted addresses
    /// @param addr - Address to verify
    modifier notBlacklisted(address addr) {
        require(!blacklist[addr], "Address blacklisted");
        _;
    }
    /// @notice Transaction cooldown period
    /// @dev Uses `rateLimitDuration` for cooldown calculation
    /// @dev Updates `lastUsed` timestamp after execution
    modifier enforceRateLimit() {
        require(
            block.timestamp >= lastUsed[msg.sender] + rateLimitDuration,
            "Rate limit: Wait cooldown period"
        );
        _;
        lastUsed[msg.sender] = block.timestamp;
    }
    /// @notice Emergency stop status
    /// @dev Ensures emergency stop is not active
    modifier emergencyNotActive() {
        require(!isEmergencyStopped, "Emergency stop active");
        _;
    }
    /// @notice Withdrawal request status
    /// @dev Enforces request state using timestamps and flags
    modifier noActiveWithdrawalRequest() {
        require(
            withdrawalRequest.requestTime == 0 || withdrawalRequest.isCancelled,
            "Active withdrawal request exists."
        );
        _;
    }
    /// @notice Withdrawal timelock period
    /// @dev Enforces withdrawal time lock period
    modifier canWithdraw() {
        require(
            block.timestamp >= withdrawalRequest.requestTime + withdrawalDelay,
            "The locking period has not expired yet"
        );
        _;
    }
    /// @notice Withdrawal request cancel
    /// @dev Ensures request wasn't cancelled
    modifier isNotCancelled() {
        require(
            !withdrawalRequest.isCancelled,
            "Withdrawal request is cancelled"
        );
        _;
    }
    /// @notice Prevents access for blacklisted addresses
    /// @dev Checks against blacklist mapping
    /// @param addr - Address to verify
    /// @dev Throws "Address blacklisted" if listed
    modifier notBlacklisted(address addr) {
        require(!blacklist[addr], "Address blacklisted");
        _;
    }
    /// @notice Enforces transaction cooldown period
    /// @dev Uses `rateLimitDuration` for cooldown calculation
    /// @dev Updates `lastUsed` timestamp after execution
    /// @dev Throws "Rate limit: Wait cooldown period" if too frequent
    modifier enforceRateLimit() {
        require(
            block.timestamp >= lastUsed[msg.sender] + rateLimitDuration,
            "Rate limit: Wait cooldown period"
        );
        _;
        lastUsed[msg.sender] = block.timestamp;
    }
    /// @notice Ensures emergency stop is not active
    /// @dev Blocks functions during emergency state
    /// @dev Throws "Emergency stop active" if triggered
    modifier emergencyNotActive() {
        require(!isEmergencyStopped, "Emergency stop active");
        _;
    }
    /// @notice Validates no pending royalty withdrawal request
    /// @dev Checks request state using timestamps and flags
    /// @dev Throws "Active withdrawal request exists" if pending
    modifier noActiveWithdrawalRequest() {
        require(
            withdrawalRequest.requestTime == 0 || withdrawalRequest.isCancelled,
            "Active withdrawal request exists."
        );
        _;
    }
    /// @notice Enforces withdrawal time lock period
    /// @dev Uses `withdrawalDelay` constant for validation
    /// @dev Throws "3 days lock period not passed yet" if waiting
    modifier canWithdraw() {
        require(
            block.timestamp >= withdrawalRequest.requestTime + withdrawalDelay,
            "3 days lock period not passed yet"
        );
        _;
    }
    /// @notice Verifies withdrawal request validity
    /// @dev Ensures request wasn't cancelled
    /// @dev Throws "Withdrawal request is cancelled" if invalid
    modifier isNotCancelled() {
        require(
            !withdrawalRequest.isCancelled,
            "Withdrawal request is cancelled"
        );
        _;
    }
    /// @notice Blacklist search
    /// @dev Checking an address in the blacklist
    modifier notBlacklisted(address addr) {
        require(!blacklist[addr], "Address blacklisted");
        _;
    }
    /// @notice Rate limit
    /// @dev Enforces cooldown between transactions
    modifier enforceRateLimit() {
        require(
            block.timestamp >= lastUsed[msg.sender] + rateLimitDuration,
            "Rate limit: Wait cooldown period"
        );
        _;
        lastUsed[msg.sender] = block.timestamp;
    }
    /// @notice Active emergency mode
    /// @dev Prevents functions from being executed when emergency stop is activated
    modifier emergencyNotActive() {
        require(!isEmergencyStopped, "Emergency stop active");
        _;
    }
    /// @notice Confirmation of the absence of withdrawal of royalty funds
    /// @dev Proof that the withdrawal request does not exist
    modifier noActiveWithdrawalRequest() {
        require(
            withdrawalRequest.requestTime == 0 || withdrawalRequest.isCancelled,
            "Existing withdrawal request exists."
        );
        _;
    }
    /// @notice Confirmation of incompleteness of the royalty withdrawal period
    /// @dev Proof that the withdrawal period has not passed
    modifier canWithdraw() {
        require(
            block.timestamp >= withdrawalRequest.requestTime + withdrawalDelay,
            "7 days lock period not passed yet"
        );
        _;
    }
    /// @notice Confirmation of the relevance of the royalty withdrawal
    /// @dev Proof that the withdrawal request was not cancelled
    modifier isNotCancelled() {
        require(
            !withdrawalRequest.isCancelled,
            "Withdrawal request is cancelled"
        );
        _;
    }
    /// @notice Confirmation of the absence of withdrawal of ETH (native coin) funds
    /// @dev Proof that the withdrawal request does not exist
    modifier noActiveETHWithdrawalRequest() {
        require(
            ethWithdrawalRequest.requestTime == 0 ||
                ethWithdrawalRequest.isCancelled,
            "Active ETH withdrawal request exists."
        );
        _;
    }
    /// @notice Confirmation of incompleteness of the withdrawal period for ETH (native coin) funds
    /// @dev Proof that the withdrawal period has not passed
    modifier canWithdrawETH() {
        require(
            block.timestamp >=
                ethWithdrawalRequest.requestTime + ETH_WITHDRAWAL_DELAY,
            "7 days lock period not passed yet"
        );
        _;
    }
    /// @notice Confirmation of the relevance of the withdrawal of ETH (native coin) funds
    /// @dev Proof that the withdrawal request was not cancelled
    modifier isNotCancelledETH() {
        require(
            !ethWithdrawalRequest.isCancelled,
            "ETH withdrawal request is cancelled"
        );
        _;
    }
    modifier notBlacklisted(address addr) {
        require(!blacklist[addr], "Address blacklisted");
        _;
    }
    modifier enforceRateLimit() {
        require(
            block.timestamp >= lastUsed[msg.sender] + 60,
            "Rate limit: Wait 60 seconds"
        );
        _;
        lastUsed[msg.sender] = block.timestamp;
    }
    constructor() payable {
        owner = msg.sender;
    }
    receive() external payable {}

    /*********************************************************************/
    /// @title Core Contract Functions
    /// @notice Base contract setup and fallback handlers
    /*********************************************************************/
    /// @notice Initializes contract
    /// @dev Sets `msg.sender` as initial owner address
    /// @dev Marked payable to enable ETH funding during deployment (the contract gets 1wei when deployed)
    constructor() payable {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(ADMIN_ROLE,    DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(MOD_ROLE,      ADMIN_ROLE);
        _setRoleAdmin(USER_ROLE,     ADMIN_ROLE);
    }
    /// @notice Contract solvency
    /// @dev Allows contract to receive ETH
    receive() external payable {}
    /// @notice Fallback calls
    /// @dev Reverts all unrecognized calls to prevents accidental execution
    fallback() external payable {
        revert("Invalid call");
    }

    /*********************************************************************/
    /// @title Multitransfer operations
    /// @notice Functions for batch transfers
    /*********************************************************************/
    /// @notice Multitransfer ETH
    /// @dev Batch transfers ETH to multiple recipients
    /// @param recipients - Array of recipient addresses
    /// @param amounts - Array of transfer amounts
    function multiTransferETH(
        address[] calldata recipients,
        uint256[] calldata amounts
    )
        external
        payable
        nonReentrant
        enforceRateLimit
        whenNotPaused
        emergencyNotActive
    {
        if (!hasRole(USER_ROLE, msg.sender)) {
        _grantRole(USER_ROLE, msg.sender);
        }
        require(recipients.length == amounts.length, "Mismatched arrays");
        uint256 allowedRecipients = extendedRecipients[msg.sender]
            ? maxRecipients
            : defaultRecipients;
        require(recipients.length <= allowedRecipients, "Too many recipients");
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < recipients.length; ) {
            require(
                recipients[i] != address(0) && !blacklist[recipients[i]],
                "Invalid recipient"
            );
            require(amounts[i] > 0, "Amount must be greater than 0");
            uint256 oldTotal = totalAmount;
            totalAmount += amounts[i];
            require(totalAmount >= oldTotal, "Overflow detected");
            unchecked {
                ++i;
            }
        }
        require(msg.value >= totalAmount + taxFee, "Insufficient ETH");
        accumulatedRoyalties += taxFee;
        uint256 localFails = 0;
        for (uint256 i = 0; i < recipients.length; ) {
            accumulatedRoyalties += taxFee;
            (bool success, ) = payable(recipients[i]).call{
                value: amounts[i],
                gas: 2300
            }("");
            if (!success) {
                localFails++;
                if (msg.sender == owner && localFails >= maxFailedTransfers) {
                    _autoEmergency("Too many failed ETH transfers");
                }
                revert("ETH transfer failed");
            }
            unchecked {
                ++i;
            }
        }
        uint256 refund = msg.value - totalAmount - taxFee;
        if (refund > 0) {
            (bool refundSuccess, ) = payable(msg.sender).call{
                value: refund,
                gas: 2300
            }("");
            require(refundSuccess, "Refund failed");
        }
    }
    /// @notice Multitransfer ERC20
    /// @dev Batch transfers ERC20 to multiple recipients
    /// @param token - Address of ERC20 token contract
    /// @param recipients - Array of valid recipient addresses
    /// @param amounts - Array of transfer amounts
    function multiTransferERC20(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    )
        external
        payable
        nonReentrant
        enforceRateLimit
        whenNotPaused
        emergencyNotActive
    {
        if (!hasRole(USER_ROLE, msg.sender)) {
        _grantRole(USER_ROLE, msg.sender);
        }
        require(token != address(0), "Invalid token address");
        require(whitelistERC20[token], "Token not whitelisted");
        require(recipients.length == amounts.length, "Mismatched arrays");
        uint256 allowedRecipients = extendedRecipients[msg.sender]
            ? maxRecipients
            : defaultRecipients;
        require(recipients.length <= allowedRecipients, "Too many recipients");
        IERC20 erc20 = IERC20(token);
        uint256 totalFee = taxFee * recipients.length;
        require(msg.value == totalFee, "Incorrect tax fee");
        accumulatedRoyalties += totalFee;
        uint256 localFails = 0;
        for (uint256 i = 0; i < recipients.length; ) {
            address to = recipients[i];
            uint256 amt = amounts[i];
            require(to != address(0) && !blacklist[to], "Invalid recipient");
            require(amt > 0, "Amount must be > 0");
            bool success = erc20.transferFrom(msg.sender, to, amt);
            if (!success) {
                localFails++;
                if (msg.sender == owner && localFails >= maxFailedTransfers) {
                    _autoEmergency("Too many failed ERC20 transfers");
                }
                revert("ERC20 transfer failed");
            }
            unchecked {
                ++i;
            }
        }
    }
    /// @notice Multitransfer ERC721
    /// @dev Batch transfers ERC721 to multiple recipients
    /// @param token - Address of ERC721 token contract
    /// @param recipients - Array of valid recipient addresses
    /// @param tokenIds - Array of ERC721 token IDs
    function multiTransferERC721(
        address token,
        address[] calldata recipients,
        uint256[] calldata tokenIds
    )
        external
        payable
        nonReentrant
        enforceRateLimit
        whenNotPaused
        emergencyNotActive
    {
        if (!hasRole(USER_ROLE, msg.sender)) {
        _grantRole(USER_ROLE, msg.sender);
        }
        require(token != address(0), "Invalid token address");
        require(whitelistERC721[token], "Token not whitelisted");
        require(recipients.length == tokenIds.length, "Mismatched arrays");
        uint256 allowedRecipients = extendedRecipients[msg.sender]
            ? maxRecipients
            : defaultRecipients;
        require(recipients.length <= allowedRecipients, "Too many recipients");
        IERC721 erc721 = IERC721(token);
        uint256 totalFee = taxFee * recipients.length;
        require(msg.value == totalFee, "Incorrect tax fee");
        accumulatedRoyalties += taxFee;
        uint256 localFails = 0;
        for (uint256 i = 0; i < recipients.length; ) {
            address to = recipients[i];
            uint256 id = tokenIds[i];
            require(to != address(0) && !blacklist[to], "Invalid recipient");
            require(erc721.ownerOf(id) == msg.sender, "Not owner of tokenId");
            try erc721.safeTransferFrom(msg.sender, to, id, "") {} catch {
                localFails++;
                if (msg.sender == owner && localFails >= maxFailedTransfers) {
                    _autoEmergency("Too many failed ERC721 transfers");
                }
                revert("ERC721 transfer failed");
            }
            unchecked {
                ++i;
            }
        }
    }
    /// @notice Multitransfer ERC1155
    /// @dev Batch transfers ERC1155 to multiple recipients
    /// @param token - ERC1155 contract address
    /// @param recipients - Array of valid recipient addresses
    /// @param amounts - Array of transfer amounts
    /// @param ids - Array of ERC1155 token IDs
    function multiTransferERC1155(
        address token,
        address[] calldata recipients,
        uint256[] calldata ids,
        uint256[] calldata amounts
    )
        external
        payable
        nonReentrant
        enforceRateLimit
        whenNotPaused
        emergencyNotActive
    {
        if (!hasRole(USER_ROLE, msg.sender)) {
        _grantRole(USER_ROLE, msg.sender);
        }
        require(token != address(0), "Invalid token address");
        require(whitelistERC1155[token], "Token not whitelisted");
        require(
            recipients.length == ids.length && ids.length == amounts.length,
            "Mismatched arrays"
        );
        uint256 allowedRecipients = extendedRecipients[msg.sender]
            ? maxRecipients
            : defaultRecipients;
        require(recipients.length <= allowedRecipients, "Too many recipients");
        IERC1155 erc1155 = IERC1155(token);
        uint256 totalFee = taxFee * recipients.length;
        require(msg.value == totalFee, "Incorrect tax fee");
        accumulatedRoyalties += totalFee;
        uint256 localFails = 0;
        for (uint256 i = 0; i < recipients.length; ) {
            address to = recipients[i];
            uint256 id = ids[i];
            uint256 amt = amounts[i];
            require(to != address(0) && !blacklist[to], "Invalid recipient");
            require(
                erc1155.balanceOf(msg.sender, id) >= amt,
                "Not enough balance"
            );
            require(amt > 0, "Amount must be > 0");
            try erc1155.safeTransferFrom(msg.sender, to, id, amt, "") {} catch {
                localFails++;
                if (msg.sender == owner && localFails >= maxFailedTransfers) {
                    _autoEmergency("Too many failed ERC1155 transfers");
                }
                revert("ERC1155 transfer failed");
            }
            unchecked {
                ++i;
            }
        }
    }

    /*********************************************************************/
    /// @title Contract Configuration
    /// @notice Functions for managing contract parameters
    /*********************************************************************/
    /// @notice Grants admin role to address
    /// @param who - Address to assign admin role
    function grantAdmin(address who) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(getRoleMemberCount(ADMIN_ROLE) < MAX_ADMINS, "Max admins");
        _grantRole(ADMIN_ROLE, who);
    }
    /// @notice Revokes admin role from address
    /// @param who - Address to remove admin role from
    function revokeAdmin(address who) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(ADMIN_ROLE, who);
    }
    /// @notice Grants moderator role to address
    /// @param who - Address to assign moderator role
    function grantMod(address who) external onlyAdmin {
        require(getRoleMemberCount(MOD_ROLE) < MAX_MODS, "Max mods");
        _grantRole(MOD_ROLE, who);
    }
    /// @notice Revokes moderator role from address
    /// @param who Address to remove moderator role from
    function revokeMod(address who) external onlyAdmin {
        _revokeRole(MOD_ROLE, who);
    }
    /// @notice Grants base user role to address
    /// @param who - Address to assign user role
    function grantUser(address who) external onlyAdmin {
        _grantRole(USER_ROLE, who);
    }
    /// @notice Revokes user role from address
    /// @param who - Address to remove user role from
    function revokeUser(address who) external onlyAdmin {
        _revokeRole(USER_ROLE, who);
    }
    /// @notice Transaction ratelimit
    /// @dev Sets transaction rate limit duration
    /// @param newDuration - New cooldown period in seconds
    function setRateLimit(uint256 newDuration) external onlyOwner {
        rateLimitDuration = newDuration;
    }
    /// @notice Extended recipient limit
    /// @dev Enables extended recipient limit for address
    /// @param user - Address to grant extended limit
    function setMaxRecipients(address user) external onlyOwner {
        extendedRecipients[user] = true;
        emit MaxRecipientsSet(user, maxRecipients);
    }
    /// @notice Default recipient limit
    /// @dev Resets recipient limit to default
    /// @param user - Address to grant default limit
    function setDefaultRecipients(address user) external onlyOwner {
        extendedRecipients[user] = false;
        emit DefaultRecipientsSet(user, defaultRecipients);
    }
    /// @notice Address type
    /// @dev Uses low-level EVM opcode to check for deployed code
    /// @param account - Address to check
    /// @return bool - True if the address contains contract code, false otherwise
    function isContract(address account) public view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
    /// @notice Blacklist management
    /// @dev Blacklisted addresses cannot interact with contract
    /// @param user - Addresses of contracts or EOA wallets
    function addBlacklist(address user) public onlyOwner {
        require(user != address(0), "Zero address cannot be blacklisted");
        require(!blacklist[user], "Address already blacklisted");
        blacklist[user] = true;
        emit BlacklistUpdated(user, true);
    }
    function batchAddBlacklist(address[] calldata users) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            require(users[i] != address(0), "Zero address");
            require(!blacklist[users[i]], "Already blacklisted");
            blacklist[users[i]] = true;
            emit BlacklistUpdated(users[i], true);
        }
    }
    function delBlacklist(address user) public onlyOwner {
        require(user != address(0), "Zero address cannot be unblacklisted");
        require(blacklist[user], "Address not in blacklist");
        blacklist[user] = false;
        emit BlacklistUpdated(user, false);
    }
    function batchDelBlacklist(address[] calldata users) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            require(users[i] != address(0), "Zero address");
            require(blacklist[users[i]], "Address not in blacklist");
            blacklist[users[i]] = false;
            emit BlacklistUpdated(users[i], false);
        }
    }
    /// @notice Whitelist management
    /// @dev Whitelisted addresses can interact with the contract
    /// @param token - ERC20 contract address
    function addWhitelistERC20(address token) public onlyOwner {
        require(isContract(token), "Address must be a contract");
        whitelistERC20[token] = true;
        emit WhitelistERC20Updated(token, true);
    }
    function batchAddWhitelistERC20(
        address[] calldata tokens
    ) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            addWhitelistERC20(tokens[i]);
        }
    }
    function delWhitelistERC20(address token) public onlyOwner {
        require(isContract(token), "Address must be a contract");
        whitelistERC20[token] = false;
        emit WhitelistERC20Updated(token, false);
    }
    function batchDelWhitelistERC20(
        address[] calldata tokens
    ) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            delWhitelistERC20(tokens[i]);
        }
    }
    /// @notice Manages ERC721 token whitelist
    /// @dev Whitelisted addresses can interact with the contract
    /// @param token - ERC721 contract address
    function addWhitelistERC721(address token) public onlyOwner {
        require(isContract(token), "Address must be a contract");
        whitelistERC721[token] = true;
        emit WhitelistERC721Updated(token, true);
    }
    function batchAddWhitelistERC721(
        address[] calldata tokens
    ) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            addWhitelistERC721(tokens[i]);
        }
    }
    function delWhitelistERC721(address token) public onlyOwner {
        require(isContract(token), "Address must be a contract");
        whitelistERC721[token] = false;
        emit WhitelistERC721Updated(token, false);
    }
    function batchDelWhitelistERC721(
        address[] calldata tokens
    ) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            delWhitelistERC721(tokens[i]);
        }
    }
    /// @notice Manages ERC1155 token whitelist
    /// @dev Whitelisted addresses can interact with the contract
    /// @param token - ERC1155 contract address
    function addWhitelistERC1155(address token) public onlyOwner {
        require(isContract(token), "Address must be a contract");
        whitelistERC1155[token] = true;
        emit WhitelistERC1155Updated(token, true);
    }
    function batchAddWhitelistERC1155(
        address[] calldata tokens
    ) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            addWhitelistERC1155(tokens[i]);
        }
    }
    function delWhitelistERC1155(address token) public onlyOwner {
        require(isContract(token), "Address must be a contract");
        whitelistERC1155[token] = false;
        emit WhitelistERC1155Updated(token, false);
    }
    function batchDelWhitelistERC1155(
        address[] calldata tokens
    ) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            delWhitelistERC1155(tokens[i]);
        }
    }
    /// @notice Initiates ownership transfer
    /// @dev Provides the current owner to transfer control to a new owner
    /// @param newOwner - Address of proposed new owner
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner address");
        pendingOwner = newOwner;
        emit OwnershipTransferInitiated(owner, newOwner);
    }
    /// @notice Initiates confirmation of transfer of ownership
    /// @dev Provides the new owner the ability to take control from the current owner
    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "Not pending owner");
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }
    /// @notice Initiates completion of ownership transfer
    /// @dev Provides the current owner permanently transfer ownership to the new owner
    function renounceOwnership() external onlyOwner {
        require(pendingOwner == address(0), "Pending owner exists");
        emit OwnershipRenounced(owner);
        owner = address(0);
    }
    /// @notice Emergency stop activation
    /// @dev Activates protection by disabling all contract functions
    /// @param reason - Reason for emergency stop (encoded in bytes32)
    function emergencyStop(bytes32 reason) external onlyOwner {
        _wasPausedBeforeEmergency = paused();
        isEmergencyStopped = true;
        emergencyReason = reason;
        if (!_wasPausedBeforeEmergency && !paused()) {
            _pause();
        }
        emit EmergencyStopActivated(msg.sender, reason);
    }
    /// @notice Emergency stop deactivation
    /// @dev Deactivates protection by enabling all contract functions
    function liftEmergencyStop() external onlyOwner {
        isEmergencyStopped = false;
        emergencyReason = "";
        if (!_wasPausedBeforeEmergency && paused()) {
            _unpause();
        }
        emit EmergencyStopLifted(msg.sender);
    }
    /// @notice Automatic emergency stop
    /// @dev Internal function for protocol self-protection mechanisms
    /// @param reasonText - Human-readable emergency reason (will be hashed)
    function _autoEmergency(string memory reasonText) internal {
        bytes32 reason = keccak256(abi.encodePacked(reasonText));
        if (isEmergencyStopped) return;
        _wasPausedBeforeEmergency = paused();
        isEmergencyStopped = true;
        emergencyReason = reason;
        if (!_wasPausedBeforeEmergency) {
            _pause();
            emit EmergencyStopActivated(address(this), reason);
        }
    }
    /// @notice Pauses contract operations
    function pause() external onlyOwner {
        require(!isEmergencyStopped, "Emergency stop active");
        _wasPausedBeforeEmergency = true;
        _pause();
    }
    /// @notice Unpauses contract operations
    function unpause() external onlyOwner {
        require(!isEmergencyStopped, "Emergency stop active");
        _wasPausedBeforeEmergency = false;
        _unpause();
    }
    /// @notice Transaction fee amount
    /// @dev Transaction fee amount, the value must be within the allowed range
    /// @param newFee - New fee value (in wei amount)
    function setTaxFee(uint256 newFee) external onlyOwner {
        require(newFee >= minTaxFee && newFee <= maxTaxFee, "Invalid fee");
        taxFee = newFee;
    }
    /// @notice Initiates withdrawal process
    /// @param amount - Amount to withdraw (in wei amount)
    /// @param isRoyalties - True for royalties, false for ETH
    function requestWithdrawal(
        uint256 amount,
        bool isRoyalties
    ) external onlyOwner noActiveWithdrawalRequest {
        uint256 availableBalance;
        if (isRoyalties) {
            availableBalance = accumulatedRoyalties;
            require(
                amount > 0 && amount <= availableBalance,
                "Invalid amount or insufficient royalties"
            );
        } else {
            availableBalance = address(this).balance - accumulatedRoyalties;
            require(
                amount > 0 && amount <= availableBalance,
                "Invalid amount or insufficient funds"
            );
        }
        withdrawalRequest = WithdrawalRequest({
            amount: amount,
            requestTime: block.timestamp,
            isCancelled: false,
            isRoyalties: isRoyalties
        });
        emit WithdrawalRequested(amount, block.timestamp);
    }
    /// @notice Initiates cancellation of a pending withdrawal
    function cancelWithdrawal() external onlyOwner {
        require(
            withdrawalRequest.requestTime > 0,
            "No withdrawal request exists"
        );
        require(!withdrawalRequest.isCancelled, "Request already cancelled");
        withdrawalRequest.isCancelled = true;
        emit WithdrawalCancelled();
    }
    /// @notice Completes withdrawal after delay
    function completeWithdrawal()
        external
        onlyOwner
        nonReentrant
        canWithdraw
        isNotCancelled
    {
        uint256 amount = withdrawalRequest.amount;
        bool isRoyalties = withdrawalRequest.isRoyalties;
        withdrawalRequest = WithdrawalRequest(0, 0, true, false);
        if (isRoyalties) {
            accumulatedRoyalties -= amount;
        } else {}
        (bool success, ) = payable(owner).call{value: amount, gas: 2300}("");
        require(success, "ETH transfer failed");
        emit WithdrawalCompleted(amount);
    }
    /// @notice Interfaces support
    /// @dev Low-level query to check supported interfaces
    /// @return - Returns True for supported interfaces (IERC20, IERC721, IERC1155).
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            super.supportsInterface(interfaceId) ||
            interfaceId == type(IERC20).interfaceId ||
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC1155).interfaceId;
    }
}