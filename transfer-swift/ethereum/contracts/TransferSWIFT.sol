// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// @openzeppelin/contracts: Import libraries
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/// @title TransferSWIFT
/// @author Bogachenko Vyacheslav
/// @notice TransferSWIFT is a universal contract for batch transfers of native coins and tokens.
/// @custom:licence License: MIT
/// @custom:version Version 0.0.0.6 (unstable)

contract TransferSWIFT is AccessControl, ReentrancyGuard, Pausable, ERC165 {
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
    /// @notice VIP user role hash
    /// @dev Grants extended privileges for premium users
    bytes32 public constant VIPUSER_ROLE = keccak256("VIPUSER_ROLE");
    /// @notice Conman role hash
    /// @dev Blocking access to all functions of the contract
    bytes32 public constant CON_ROLE = keccak256("CON_ROLE");
    /// @notice Maximum administrator count
    uint256 public constant MAX_ADMINS = 3;
    /// @notice Maximum moderator count
    uint256 public constant MAX_MODS = 10;
    /// @notice Current royalty withdrawal request
    /// @dev Stores pending request details (address, amount, timestamp)
    WithdrawalRequest public withdrawalRequest;
    /// @notice Royalty withdrawal cooldown period
    /// @dev Security delay of 3 days (3 * 86400 seconds)
    uint256 public constant withdrawalDelay = 3 days;
    /// @notice Using Address library for safe ETH operations
    using Address for address payable;
    /// @notice Using SafeERC20 library for safe ERC-20 operations
    using SafeERC20 for IERC20;
    /// @notice Current contract owner address
    address public owner;
    /// @notice Pending ownership candidate address
    /// @dev Used for two-step ownership transfer
    address public pendingOwner;
    /// @notice Protocol display name
    /// @dev Used for interface identification
    string public name = "TransferSWIFT";
    /// @notice Protocol symbol
    /// @dev Used for interface identification
    string public symbol = "SWIFT";
    /// @notice Current transaction fee
    /// @dev Default value: 0.0001 ETH (1e14 wei)
    /// @dev Must be in range [minTaxFee, maxTaxFee]
    uint256 public taxFee = 1e14;
    /// @notice Minimum allowed fee
    /// @dev Value: 0.000001 ETH (1e12 wei)
    uint256 public minTaxFee = 1e12;
    /// @notice Maximum allowed fee
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
    /// @dev When activated, blocks main contract functions
    bool public isEmergencyStopped;
    /// @dev Stores pause state before emergency activation
    bool private _wasPausedBeforeEmergency;
    /// @notice Emergency activation reason
    /// @dev Stores hashed message describing the reason
    bytes32 public emergencyReason;
    /// @notice Limit of failed transfers for automatic activation of emergencyStop
    uint256 public constant maxFailedTransfers = 3;

    /*********************************************************************/
    /// @title Contract access control and restrictions
    /// @notice This section contains permission mappings and usage restrictions
    /*********************************************************************/
    /// @notice Last usage timestamp for rate limiting
    /// @dev Stores block timestamps for address-based cooldown tracking
    /// @param userAddress - Address being queried
    /// @return timestamp - Last interaction time (UNIX format)
    mapping(address => uint256) public lastUsed;
    /// @notice List of prohibited addresses
    /// @dev Blocked addresses cannot interact with key functions
    /// @param targetAddress - Address being checked
    /// @return status - True if address is blacklisted
    mapping(address => bool) public blacklist;
    /// @notice Addresses with increased recipient allowances
    /// @dev When true, allows bypassing default recipient limits
    /// @param userAddress - Address being checked
    /// @return hasExtendedLimit - True if extended limit is granted
    mapping(address => bool) public extendedRecipients;
    /// @notice Allowed ERC20 tokens for operations
    /// @dev Token contract addresses permitted for transactions
    /// @param tokenAddress - ERC20 contract address
    /// @return isWhitelisted - True if token is approved
    mapping(address => bool) public whitelistERC20;
    /// @notice Allowed ERC721 tokens for operations
    /// @dev NFT contract addresses permitted for transactions
    /// @param tokenAddress - ERC721 contract address
    /// @return isWhitelisted - True if token is approved
    mapping(address => bool) public whitelistERC721;
    /// @notice Allowed ERC1155 tokens for operations
    /// @dev NFT contract addresses permitted for transactions
    /// @param tokenAddress - ERC1155 contract address
    /// @return isWhitelisted - True if token is approved
    mapping(address => bool) public whitelistERC1155;

    /*********************************************************************/
    /// @notice Contains data structures for handling contract requests
    /// @dev Implements security measures using templates
    /*********************************************************************/
    /// @title Royalty Withdrawal Request Structure
    /// @notice Represents a pending royalty withdrawal request
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
    /// @notice Emitted when royalties are withdrawn
    /// @dev Indicates successful royalty distribution
    /// @param receiver - Royalty recipient address (always owner)
    /// @param amount - Withdrawn amount in wei
    event RoyaltiesWithdrawn(address indexed receiver, uint256 amount);
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
    /// @dev Overrides defaultRecipients for specific address
    /// @param user - Address receiving limit extension
    /// @param limit - New maximum recipient allowance
    event MaxRecipientsSet(address indexed user, uint256 limit);
    /// @notice Emitted when recipient limit is reset
    /// @dev Restores defaultRecipients value for address
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
    /// @dev Controls allowed NFTs for operations
    /// @param token - ERC721 contract address
    /// @param status - New status (true = allowed)
    event WhitelistERC721Updated(address indexed token, bool status);
    /// @notice Emitted when ERC1155 token is whitelisted
    /// @dev Controls allowed multi-tokens for operations
    /// @param token - ERC1155 contract address
    /// @param status - New status (true = allowed)
    event WhitelistERC1155Updated(address indexed token, bool status);

    /*********************************************************************/
    /// @title Access Control Modifiers
    /// @notice Modifiers for permission checks
    /*********************************************************************/
    /// @notice Restricts function to contract owner only
    /// @dev Verifies `msg.sender` matches stored owner address
    /// @dev Throws "Not owner" on failure
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
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
    /// @notice Restricts access to admin role holders
    /// @dev Verifies caller has ADMIN_ROLE
    /// @dev Admins have highest privilege level
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Not admin");
        _;
    }
    /// @notice Restricts access to moderator role holders
    /// @dev Verifies caller has MOD_ROLE
    /// @dev Moderators have elevated privileges for content management
    modifier onlyMod() {
        require(hasRole(MOD_ROLE, msg.sender), "Not mod");
        _;
    }
    /// @notice Restricts access to admin or moderator accounts
    /// @dev Combines ADMIN_ROLE and MOD_ROLE checks in single modifier
    /// @dev Security:
    /// - Provides tiered access to sensitive functions
    modifier root() {
        require(
            hasRole(ADMIN_ROLE, msg.sender) || hasRole(MOD_ROLE, msg.sender),
            "Not root"
        );
        _;
    }
    /// @notice Restricts access to user role holders
    /// @dev Verifies caller has USER_ROLE
    /// @dev Base access level for registered users
    modifier onlyUser() {
        require(hasRole(USER_ROLE, msg.sender), "Not user");
        _;
    }
    /// @notice Restricts access to VIP user role holders
    /// @dev Verifies caller has VIPUSER_ROLE
    /// @dev Grants access to premium features
    modifier onlyVIP() {
        require(hasRole(VIPUSER_ROLE, msg.sender), "Not vip");
        _;
    }
    /// @notice Restricts access to conman role holders
    /// @dev Prevents smart contract interactions
    /// @dev Mitigates bot/front-running risks
    modifier notCon() {
        require(!hasRole(CON_ROLE, msg.sender), "You are a con");
        _;
    }

    /*********************************************************************/
    /// @title Core Contract Functions
    /// @notice Base contract setup and fallback handlers
    /*********************************************************************/
    /// @notice Initializes contract with deployer as owner
    /// @dev Sets `msg.sender` as initial owner address
    /// @dev Marked payable to enable ETH funding during deployment
    constructor() payable {
        // Set contract owner
        owner = msg.sender;
        // Grant initial roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        // Configure role administration hierarchy
        _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(MOD_ROLE, ADMIN_ROLE);
        _setRoleAdmin(USER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(VIPUSER_ROLE, MOD_ROLE);
        _setRoleAdmin(CON_ROLE, MOD_ROLE);
    }
    /// @notice Allows contract to receive ETH
    /// @dev Automatic trigger on plain ETH transfers
    receive() external payable {}
    /// @notice Fallback for invalid function calls
    /// @dev Reverts all unrecognized calls
    /// @dev Prevents accidental execution
    fallback() external payable {
        revert("Invalid call");
    }
    /// @notice Grants admin role to address
    /// @param who - Address to assign admin role
    /// @dev Requirements:
    /// - Caller must have DEFAULT_ADMIN_ROLE
    /// - Must not exceed MAX_ADMINS limit
    /// - Recipient address must not have CON_ROLE
    function grantAdmin(address who) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(getRoleMemberCount(ADMIN_ROLE) < MAX_ADMINS, "Max admins");
        _grantRole(ADMIN_ROLE, who);
    }
    /// @notice Revokes admin role from address
    /// @param who - Address to remove admin role from
    /// @dev Requirements:
    /// - Caller must have DEFAULT_ADMIN_ROLE
    /// - Cannot revoke last DEFAULT_ADMIN_ROLE
    function revokeAdmin(address who) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(ADMIN_ROLE, who);
    }
    /// @notice Grants moderator role to address
    /// @param who Address to assign moderator role
    /// @dev Requirements:
    /// - Caller must have ADMIN_ROLE
    /// - Must not exceed MAX_MODS limit
    function grantMod(address who) external onlyAdmin {
        require(getRoleMemberCount(MOD_ROLE) < MAX_MODS, "Max mods");
        _grantRole(MOD_ROLE, who);
    }
    /// @notice Revokes moderator role from address
    /// @param who Address to remove moderator role from
    function revokeMod(address who) external onlyAdmin {
        _revokeRole(MOD_ROLE, who);
        if (!hasRole(USER_ROLE, who)) {
            _grantRole(USER_ROLE, who);
        }
    }
    /// @notice Grants base user role to address
    /// @param who Address to assign user role
    /// @dev Can also be auto-granted on first interaction
    function grantUser(address who) external root {
        _grantRole(USER_ROLE, who);
    }
    /// @notice Revokes user role from address
    /// @param who Address to remove user role from
    function revokeUser(address who) external root {
        _revokeRole(USER_ROLE, who);
        _grantRole(USER_ROLE, who);
    }
    /// @notice Grants VIP user role to address
    /// @param who Address to assign VIP role
    function grantVIP(address who) external root {
        _grantRole(VIPUSER_ROLE, who);
    }
    /// @notice Revokes VIP user role from address
    /// @param who Address to remove VIP role from
    function revokeVIP(address who) external root {
        _revokeRole(VIPUSER_ROLE, who);
        if (!hasRole(USER_ROLE, who)) {
            _grantRole(USER_ROLE, who);
        }
    }
    /// @notice Grants conman role to address
    /// @param who Address to assign con role
    /// @dev Requirements:
    /// - Automatically removes USER and VIP roles
    /// - Recipient must be a smart contract
    function grantCon(address who) external root {
        if (hasRole(USER_ROLE, who)) _revokeRole(USER_ROLE, who);
        if (hasRole(VIPUSER_ROLE, who)) _revokeRole(VIPUSER_ROLE, who);
        if (hasRole(MOD_ROLE, who)) _revokeRole(MOD_ROLE, who);
        if (hasRole(ADMIN_ROLE, who)) revert("Cannot block admin");
        _grantRole(CON_ROLE, who);
    }
    /// @notice Revokes contract role from address
    /// @param who Address to remove contract role from
    function revokeCon(address who) external root {
        _revokeRole(CON_ROLE, who);
    }
    /*********************************************************************/
    /// @title ETH Transfer Operations
    /// @notice Functions for native currency batch transfers
    /*********************************************************************/
    /// @notice Batch transfers ETH to multiple recipients
    /// @dev Implements fee collection and safety checks
    /// @param recipients - Array of recipient addresses
    /// @param amounts - Array of ETH amounts in wei
    /// @dev Requirements:
    /// - Arrays must be same length
    /// - Recipient count within allowed limits
    /// - Valid recipient addresses
    /// - Sufficient ETH sent (amounts + taxFee)
    /// @dev Security:
    /// - Reentrancy protection
    /// - Rate limiting
    /// - Emergency stop check
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
        notCon
    {
        if (
            !hasRole(USER_ROLE, msg.sender) &&
            !hasRole(VIPUSER_ROLE, msg.sender)
        ) {
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

    /*********************************************************************/
    /// @title ERC20 Transfer Operations
    /// @notice Functions for fungible token batch transfers
    /*********************************************************************/
    /// @notice Batch transfers ERC20 tokens to multiple recipients
    /// @dev Executes transferFrom for each recipient with fee validation
    /// @param token - Address of ERC20 token contract (must be whitelisted)
    /// @param recipients - Array of valid non-zero recipient addresses
    /// @param amounts - Array of transfer amounts (must be > 0)
    /// @dev Throws:
    /// - "Invalid token address" for zero address
    /// - "Token not whitelisted" if not in allowed list
    /// - "Mismatched arrays" for length mismatch
    /// - "Too many recipients" exceeds limit
    /// - "Invalid recipient" for blacklisted/zero address
    /// - "ERC20 transfer failed" on transfer errors
    /// - "Incorrect tax fee" for wrong ETH amount
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
        notCon
    {
        if (
            !hasRole(USER_ROLE, msg.sender) &&
            !hasRole(VIPUSER_ROLE, msg.sender)
        ) {
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
        accumulatedRoyalties += taxFee;
        require(msg.value == taxFee, "Incorrect tax fee");
        uint256 localFails = 0;
        for (uint256 i = 0; i < recipients.length; ) {
            address to = recipients[i];
            uint256 amt = amounts[i];
            require(to != address(0) && !blacklist[to], "Invalid recipient");
            require(amt > 0, "Amount must be > 0");
            try erc20.safeTransferFrom(msg.sender, to, amt) {} catch {
                localFails++;
                if (msg.sender == owner && localFails >= maxFailedTransfers) {
                    _autoEmergency("Too many failed ERC20 transfers");
                }
                unchecked {
                    ++i;
                }
            }
        }
    }
    /*********************************************************************/
    /// @title ERC-721 Transfer Operations
    /// @notice Functions for fungible token batch transfers
    /*********************************************************************/
    /// @notice Batch transfers ERC721 tokens
    /// @dev Uses safeTransferFrom for NFT handling
    /// @param token - ERC721 contract address
    /// @param recipients - Array of recipient addresses
    /// @param tokenIds - Array of NFT token IDs
    /// @dev Requirements:
    /// - Caller must own all tokens
    /// - Valid whitelisted contract
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
        notCon
    {
        if (
            !hasRole(USER_ROLE, msg.sender) &&
            !hasRole(VIPUSER_ROLE, msg.sender)
        ) {
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
        accumulatedRoyalties += taxFee;
        require(msg.value == taxFee, "Incorrect tax fee");
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

    /*********************************************************************/
    /// @title ERC-1155 Transfer Operations
    /// @notice Functions for fungible token batch transfers
    /*********************************************************************/
    /// @notice Batch transfers ERC1155 tokens
    /// @dev Handles both fungible and non-fungible tokens
    /// @param token - ERC1155 contract address
    /// @param recipients - Array of recipient addresses
    /// @param ids - Array of token IDs
    /// @param amounts - Array of token amounts
    /// @dev Requirements:
    /// - Consistent array lengths
    /// - Sufficient token balances
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
        notCon
    {
        if (
            !hasRole(USER_ROLE, msg.sender) &&
            !hasRole(VIPUSER_ROLE, msg.sender)
        ) {
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
        accumulatedRoyalties += taxFee;
        require(msg.value == taxFee, "Incorrect tax fee");
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
    /// @notice Functions for managing contract parameters and limits
    /*********************************************************************/
    /// @notice Sets transaction rate limit duration
    /// @dev Only affects future transactions
    /// @param newDuration - New cooldown period in seconds
    /// @dev Requirements:
    /// - Caller must be owner
    function setRateLimit(uint256 newDuration) external onlyOwner {
        rateLimitDuration = newDuration;
    }
    /// @notice Enables extended recipient limit for address
    /// @dev Sets maximum allowed recipients to maxRecipients
    /// @param user - Address to grant extended limit
    function setMaxRecipients(address user) external onlyOwner {
        extendedRecipients[user] = true;
        emit MaxRecipientsSet(user, maxRecipients);
    }
    /// @notice Resets recipient limit to default
    /// @dev Sets maximum allowed recipients to defaultRecipients
    /// @param user - Address to reset limit
    function setDefaultRecipients(address user) external onlyOwner {
        extendedRecipients[user] = false;
        emit DefaultRecipientsSet(user, defaultRecipients);
    }
    /// @notice Checks if an address is a smart contract
    /// @dev Uses low-level EVM opcode to check for deployed code
    /// @param account Address to check
    /// @return bool True if the address contains contract code, false otherwise
    /// @dev Security Considerations:
    /// - Returns false during contract construction (constructor execution)
    /// - Not reliable for precompiled contracts (0x1-0xffff)
    /// - May return false positives for destroyed contracts
    /// @dev When to use:
    /// - Smart contract whitelisting
    function isContract(address account) public view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
    /// @notice Adds address to blacklist
    /// @dev Blacklisted addresses cannot interact with contract
    /// @param user - Address to blacklist
    function addBlacklist(address user) external root {
        blacklist[user] = true;
        emit BlacklistUpdated(user, true);
    }
    function delBlacklist(address user) external root {
        blacklist[user] = false;
        emit BlacklistUpdated(user, false);
    }
    /// @notice Manages ERC20 token whitelist
    /// @param token - ERC20 contract address
    function addWhitelistERC20(address token) external root {
        require(isContract(token), "Address must be a contract");
        whitelistERC20[token] = true;
        emit WhitelistERC20Updated(token, true);
    }
    function delWhitelistERC20(address token) external root {
        require(isContract(token), "Address must be a contract");
        whitelistERC20[token] = false;
        emit WhitelistERC20Updated(token, false);
    }
    /// @notice Manages ERC721 token whitelist
    /// @param token - ERC721 contract address
    function addWhitelistERC721(address token) external root {
        require(isContract(token), "Address must be a contract");
        whitelistERC721[token] = true;
        emit WhitelistERC721Updated(token, true);
    }
    function delWhitelistERC721(address token) external root {
        require(isContract(token), "Address must be a contract");
        whitelistERC721[token] = false;
        emit WhitelistERC721Updated(token, false);
    }
    /// @notice Manages ERC1155 token whitelist
    /// @param token - ERC1155 contract address
    function addWhitelistERC1155(address token) external root {
        require(isContract(token), "Address must be a contract");
        whitelistERC1155[token] = true;
        emit WhitelistERC1155Updated(token, true);
    }
    function delWhitelistERC1155(address token) external root {
        require(isContract(token), "Address must be a contract");
        whitelistERC1155[token] = false;
        emit WhitelistERC1155Updated(token, false);
    }
    /// @notice Initiates ownership transfer
    /// @param newOwner - Address of proposed new owner
    /// @dev New owner must call acceptOwnership
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner address");
        pendingOwner = newOwner;
        emit OwnershipTransferInitiated(owner, newOwner);
    }
    /// @notice Completes ownership transfer
    /// @dev Requirements:
    /// - Caller must be pendingOwner
    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "Not pending owner");
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }
    /// @notice Renounces ownership permanently
    /// @dev Requirements:
    /// - No pending ownership transfer
    function renounceOwnership() external onlyOwner {
        require(pendingOwner == address(0), "Pending owner exists");
        emit OwnershipRenounced(owner);
        owner = address(0);
    }
    /// @notice Activates emergency stop
    /// @param reason - Bytes32 encoded reason
    /// @dev Automatically pauses if not already paused
    function emergencyStop(bytes32 reason) external onlyOwner {
        _wasPausedBeforeEmergency = paused();
        isEmergencyStopped = true;
        emergencyReason = reason;
        if (!_wasPausedBeforeEmergency && !paused()) {
            _pause();
        }
        emit EmergencyStopActivated(msg.sender, reason);
    }
    /// @notice Deactivates emergency stop
    /// @dev Restores previous pause state
    function liftEmergencyStop() external onlyOwner {
        isEmergencyStopped = false;
        emergencyReason = "";
        if (!_wasPausedBeforeEmergency && paused()) {
            _unpause();
        }
        emit EmergencyStopLifted(msg.sender);
    }
    /// @notice Automatically activates emergency stop with hashed reason
    /// @dev Internal function for protocol self-protection mechanisms
    /// @param reasonText - Human-readable emergency reason (will be hashed)
    /// @dev Features:
    /// - Auto-pauses contract if not already paused
    /// - Hashes reason text for gas efficiency
    /// - Idempotent (no-op if already in emergency)
    /// @dev Security:
    /// - Maintains pre-emergency pause state
    /// - Emits event only on state change
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
    /// @notice Updates transaction fee amount
    /// @dev Must be within minTaxFee-maxTaxFee range
    /// @param newFee - New fee value in wei
    /// @dev Requirements:
    /// - newFee >= minTaxFee
    /// - newFee <= maxTaxFee
    function setTaxFee(uint256 newFee) external onlyOwner {
        require(newFee >= minTaxFee && newFee <= maxTaxFee, "Invalid fee");
        taxFee = newFee;
    }
    /// @notice Initiates withdrawal process
    /// @param amount - Amount to withdraw in wei
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
    /// @notice Cancels pending withdrawal
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
    /// @notice Withdraws available balance
    function withdrawFunds() external onlyOwner nonReentrant {
        require(
            withdrawalRequest.requestTime == 0 || withdrawalRequest.isCancelled,
            "Active withdrawal request exists"
        );
        uint256 availableBalance = address(this).balance - accumulatedRoyalties;
        require(availableBalance > 0, "No available funds");
        payable(owner).sendValue(availableBalance);
        emit FundsWithdrawn(owner, availableBalance);
    }
    /// @notice Pauses contract operations
    /// @dev Cannot pause during emergency stop
    function pause() external onlyOwner {
        require(!isEmergencyStopped, "Emergency stop active");
        _wasPausedBeforeEmergency = true;
        _pause();
    }
    /// @notice Unpauses contract operations
    /// @dev Cannot unpause during emergency stop
    function unpause() external onlyOwner {
        require(!isEmergencyStopped, "Emergency stop active");
        _wasPausedBeforeEmergency = false;
        _unpause();
    }
    /// @notice Checks interface support
    /// @dev Returns true for supported interfaces (IERC20, IERC721, IERC1155).
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override notCon returns (bool) {
        if (
            !hasRole(USER_ROLE, msg.sender) &&
            !hasRole(VIPUSER_ROLE, msg.sender)
        ) {
            _grantRole(USER_ROLE, msg.sender);
        }
        return
            super.supportsInterface(interfaceId) ||
            interfaceId == type(IERC20).interfaceId ||
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC1155).interfaceId;
    }
}