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
import "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";

/// @title TransferSWIFT
/// @author Bogachenko Vyacheslav
/// @notice TransferSWIFT is a universal contract for batch transfers of native coins and tokens.
/// @custom:licence License: MIT
/// @custom:version Version 0.0.0.8 (unstable)

contract TransferSWIFT is AccessControlEnumerable, ReentrancyGuard, Pausable {
    /*********************************************************************/
    /// @title Contract configuration and state parameters
    /// @notice This section contains contract state variables and settings
    /*********************************************************************/
    /// @notice Administrator role hash
    /// @dev Grants full access to contract management
    /// @dev Should be granted cautiously
    bytes32 public constant adminRole = keccak256("adminRole");
    /// @notice Moderator role hash
    /// @dev Grants access to moderation functions
    /// @dev Should be granted cautiously
    bytes32 public constant modRole = keccak256("modRole");
    /// @notice Maximum administrator count
    uint256 public constant maxAdmins = 3;
    /// @notice Maximum moderator count
    uint256 public constant maxMods = 10;
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
    /// @dev Absolute maximum: 30 recipients
    uint256 constant maxRecipients = 30;
    /// @notice Current allowed number of recipients per transaction
    /// @dev Value range: [defaultRecipients, maxRecipients]
    uint256 public currentRecipients = defaultRecipients;
    /// @notice Rate limiting duration
    /// @dev Default value: 60 seconds (1 minute)
    uint256 public rateLimitDuration = 60;
    /// @notice Contract emergency stop flag
    /// @dev Blocking the main functions of the contract
    bool public isEmergencyStopped;
    /// @dev Maintaining a pause state before emergency activation
    bool private _wasPausedBeforeEmergency;
    /// @notice Emergency activation reason
    /// @dev Saving a hashed message describing the reason
    bytes32 public emergencyReason;

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
        uint256 availableEthBalance;
        uint256 availableRoyaltiesBalance;
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
    /// @notice Emitted when the rate limit duration is updated
    /// @dev Indicates a change in the cooldown period between transactions
    /// @param newDuration - New rate limit duration in seconds
    event RateLimitUpdated(uint256 indexed newDuration);
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
    /// @notice Emitted when the transaction fee is updated
    /// @dev Signals a change in the protocol's tax fee percentage
    /// @param newFee - New fee value in wei
    event TaxFeeUpdated(uint256 indexed newFee);

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
    /// @notice Restricts access to administrator role holders
    /// @dev Admins have highest privilege level
    modifier onlyAdmin() {
        require(hasRole(adminRole, msg.sender), "Not admin");
        _;
    }
    /// @notice Restricts access to moderator role holders
    /// @dev Moderators have elevated privileges for content management
    modifier onlyMod() {
        require(hasRole(modRole, msg.sender), "Not mod");
        _;
    }
    /// @notice Restricts access to administrators or moderators role holders
    /// @dev Combines two role checks into single modifier
    modifier onlyRoot() {
        require(
            hasRole(adminRole, msg.sender) || hasRole(modRole, msg.sender),
            "Caller is not admin or mod"
        );
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
        lastUsed[msg.sender] = block.timestamp;
        _;
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

    /*********************************************************************/
    /// @title Core Contract Functions
    /// @notice Base contract setup and fallback handlers
    /*********************************************************************/
    /// @notice Initializes contract
    /// @dev Sets `msg.sender` as initial owner address
    /// @dev Marked payable to enable ETH funding during deployment (the contract gets 1wei when deployed)
    constructor() payable {
        owner = msg.sender;
        _grantRole(adminRole, msg.sender);
        _setRoleAdmin(adminRole, adminRole);
        _setRoleAdmin(modRole, adminRole);
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
        require(recipients.length == amounts.length, "Mismatched arrays");
        uint256 allowedRecipients = extendedRecipients[msg.sender]
            ? maxRecipients
            : defaultRecipients;
        require(recipients.length <= currentRecipients, "Too many recipients");
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
        for (uint256 i = 0; i < recipients.length; ) {
            (bool success, ) = payable(recipients[i]).call{
                value: amounts[i],
                gas: 2300
            }("");
            unchecked {
                ++i;
            }
        }
        accumulatedRoyalties += taxFee;
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
        require(token != address(0), "Invalid token address");
        require(whitelistERC20[token], "Token not whitelisted");
        require(recipients.length == amounts.length, "Mismatched arrays");
        require(
            IERC165(token).supportsInterface(type(IERC20).interfaceId),
            "Not an ERC20 token"
        );
        uint256 allowedRecipients = extendedRecipients[msg.sender]
            ? maxRecipients
            : defaultRecipients;
        require(recipients.length <= currentRecipients, "Too many recipients");
        IERC20 erc20 = IERC20(token);
        uint256 totalFee = taxFee * recipients.length;
        require(msg.value == totalFee, "Incorrect tax fee");
        accumulatedRoyalties += totalFee;
        for (uint256 i = 0; i < recipients.length; ) {
            address to = recipients[i];
            uint256 amt = amounts[i];
            require(to != address(0) && !blacklist[to], "Invalid recipient");
            require(amt > 0, "Amount must be > 0");
            bool success = erc20.transferFrom(msg.sender, to, amt);
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
        require(token != address(0), "Invalid token address");
        require(whitelistERC721[token], "Token not whitelisted");
        require(recipients.length == tokenIds.length, "Mismatched arrays");
        require(
            IERC165(token).supportsInterface(type(IERC721).interfaceId),
            "Not an ERC721 token"
        );
        uint256 allowedRecipients = extendedRecipients[msg.sender]
            ? maxRecipients
            : defaultRecipients;
        require(recipients.length <= currentRecipients, "Too many recipients");
        IERC721 erc721 = IERC721(token);
        uint256 totalFee = taxFee * recipients.length;
        require(msg.value == totalFee, "Incorrect tax fee");
        accumulatedRoyalties += taxFee;
        for (uint256 i = 0; i < recipients.length; ) {
            address to = recipients[i];
            uint256 id = tokenIds[i];
            require(to != address(0) && !blacklist[to], "Invalid recipient");
            if (isContract(to)) {
                require(
                    IERC721Receiver(to).onERC721Received(
                        msg.sender,
                        msg.sender,
                        id,
                        ""
                    ) == IERC721Receiver.onERC721Received.selector,
                    "ERC721: Receiver rejected"
                );
            }
            try erc721.safeTransferFrom(msg.sender, to, id, "") {} catch {
                unchecked {
                    ++i;
                }
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
        require(token != address(0), "Invalid token address");
        require(whitelistERC1155[token], "Token not whitelisted");
        require(
            recipients.length == ids.length && ids.length == amounts.length,
            "Mismatched arrays"
        );
        require(
            IERC165(token).supportsInterface(type(IERC1155).interfaceId),
            "Not an ERC1155 token"
        );
        uint256 allowedRecipients = extendedRecipients[msg.sender]
            ? maxRecipients
            : defaultRecipients;
        require(recipients.length <= currentRecipients, "Too many recipients");
        IERC1155 erc1155 = IERC1155(token);
        uint256 totalFee = taxFee * recipients.length;
        require(msg.value == totalFee, "Incorrect tax fee");
        accumulatedRoyalties += totalFee;
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
            if (isContract(to)) {
                try
                    IERC1155Receiver(to).onERC1155Received(
                        msg.sender,
                        msg.sender,
                        id,
                        amt,
                        ""
                    )
                returns (bytes4 response) {
                    require(
                        response == IERC1155Receiver.onERC1155Received.selector,
                        "ERC1155: Receiver rejected"
                    );
                } catch {
                    revert("ERC1155: Transfer to non-receiver contract");
                }
            }
            try erc1155.safeTransferFrom(msg.sender, to, id, amt, "") {} catch {
                unchecked {
                    ++i;
                }
            }
        }
    }
    /*********************************************************************/
    /// @title Contract Configuration
    /// @notice Functions for managing contract parameters
    /*********************************************************************/
    /// @notice Grants a specific role to an address
    /// @dev Includes additional safeguards for role capacity limits
    /// @param role - The role identifier to grant (bytes32)
    /// @param account - The address receiving the role
    function grantRole(
        bytes32 role,
        address account
    )
        public
        override(AccessControlEnumerable, IAccessControlEnumerable)
        onlyAdmin
    {
        require(account != address(0), "Zero address");
        require(!isContract(account), "Address must not be a contract");
        require(!hasRole(role, account), "Account already has this role");
        if (role == adminRole) {
            require(getRoleMemberCount(adminRole) < maxAdmins, "Max admins");
        }
        if (role == modRole) {
            require(getRoleMemberCount(modRole) < maxMods, "Max mods");
        }
        _grantRole(role, account);
        emit RoleGranted(role, account, msg.sender);
    }
    /// @notice Revokes a role from an address
    /// @param role - The role identifier to revoke
    /// @param account - The address losing the role
    function revokeRole(
        bytes32 role,
        address account
    )
        public
        override(AccessControlEnumerable, IAccessControlEnumerable)
        onlyAdmin
    {
        if (role == adminRole) {
            require(
                getRoleMemberCount(adminRole) > 1,
                "Cannot remove last admin"
            );
            require(account != msg.sender, "Self-removal forbidden");
        }
        _revokeRole(role, account);
        emit RoleRevoked(role, account, msg.sender);
    }
    /// @notice Transaction ratelimit
    /// @dev Sets transaction rate limit duration
    /// @param newDuration - New cooldown period in seconds
    function setRateLimit(uint256 newDuration) external onlyRoot {
        rateLimitDuration = newDuration;
        emit RateLimitUpdated(newDuration);
    }
    /// @notice Extended recipient limit
    /// @dev Enables extended recipient limit for address
    /// @param user - Address to grant extended limit
    function setMaxRecipients(address user) external onlyRoot {
        extendedRecipients[user] = true;
        emit MaxRecipientsSet(user, maxRecipients);
    }
    /// @notice Default recipient limit
    /// @dev Resets recipient limit to default
    /// @param user - Address to grant default limit
    function setDefaultRecipients(address user) external onlyRoot {
        extendedRecipients[user] = false;
        emit DefaultRecipientsSet(user, defaultRecipients);
    }
    /// @notice Current recipients limit
    /// @dev Updates the allowed number of recipients for a single transaction
    /// @param newLimit - New recipient limit to set
    function updateSetRecipients(uint256 newLimit) external onlyRoot {
        require(
            newLimit >= defaultRecipients && newLimit <= maxRecipients,
            "Limit out of bounds"
        );
        setRecipients = newLimit;
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
    function addBlacklist(address user) public onlyRoot {
        require(user != address(0), "Zero address cannot be blacklisted");
        require(!blacklist[user], "Address already blacklisted");
        blacklist[user] = true;
        emit BlacklistUpdated(user, true);
    }
    function batchAddBlacklist(address[] calldata users) external onlyRoot {
        for (uint256 i = 0; i < users.length; i++) {
            require(users[i] != address(0), "Zero address");
            require(!blacklist[users[i]], "Already blacklisted");
            blacklist[users[i]] = true;
            emit BlacklistUpdated(users[i], true);
        }
    }
    function delBlacklist(address user) public onlyRoot {
        require(user != address(0), "Zero address cannot be unblacklisted");
        require(blacklist[user], "Address not in blacklist");
        blacklist[user] = false;
        emit BlacklistUpdated(user, false);
    }
    function batchDelBlacklist(address[] calldata users) external onlyRoot {
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
    function addWhitelistERC20(address token) public onlyRoot {
        require(isContract(token), "Address must be a contract");
        whitelistERC20[token] = true;
        emit WhitelistERC20Updated(token, true);
    }
    function batchAddWhitelistERC20(
        address[] calldata tokens
    ) external onlyRoot {
        for (uint256 i = 0; i < tokens.length; i++) {
            addWhitelistERC20(tokens[i]);
        }
    }
    function delWhitelistERC20(address token) public onlyRoot {
        require(isContract(token), "Address must be a contract");
        require(whitelistERC20[token], "Token not in whitelist");
        whitelistERC20[token] = false;
        emit WhitelistERC20Updated(token, false);
    }
    function batchDelWhitelistERC20(
        address[] calldata tokens
    ) external onlyRoot {
        for (uint256 i = 0; i < tokens.length; i++) {
            delWhitelistERC20(tokens[i]);
        }
    }
    /// @notice Manages ERC721 token whitelist
    /// @dev Whitelisted addresses can interact with the contract
    /// @param token - ERC721 contract address
    function addWhitelistERC721(address token) public onlyRoot {
        require(isContract(token), "Address must be a contract");
        whitelistERC721[token] = true;
        emit WhitelistERC721Updated(token, true);
    }
    function batchAddWhitelistERC721(
        address[] calldata tokens
    ) external onlyRoot {
        for (uint256 i = 0; i < tokens.length; i++) {
            addWhitelistERC721(tokens[i]);
        }
    }
    function delWhitelistERC721(address token) public onlyRoot {
        require(isContract(token), "Address must be a contract");
        require(whitelistERC721[token], "Token not in whitelist");
        whitelistERC721[token] = false;
        emit WhitelistERC721Updated(token, false);
    }
    function batchDelWhitelistERC721(
        address[] calldata tokens
    ) external onlyRoot {
        for (uint256 i = 0; i < tokens.length; i++) {
            delWhitelistERC721(tokens[i]);
        }
    }
    /// @notice Manages ERC1155 token whitelist
    /// @dev Whitelisted addresses can interact with the contract
    /// @param token - ERC1155 contract address
    function addWhitelistERC1155(address token) public onlyRoot {
        require(isContract(token), "Address must be a contract");
        whitelistERC1155[token] = true;
        emit WhitelistERC1155Updated(token, true);
    }
    function batchAddWhitelistERC1155(
        address[] calldata tokens
    ) external onlyRoot {
        for (uint256 i = 0; i < tokens.length; i++) {
            addWhitelistERC1155(tokens[i]);
        }
    }
    function delWhitelistERC1155(address token) public onlyRoot {
        require(isContract(token), "Address must be a contract");
        require(whitelistERC1155[token], "Token not in whitelist");
        whitelistERC1155[token] = false;
        emit WhitelistERC1155Updated(token, false);
    }
    function batchDelWhitelistERC1155(
        address[] calldata tokens
    ) external onlyRoot {
        for (uint256 i = 0; i < tokens.length; i++) {
            delWhitelistERC1155(tokens[i]);
        }
    }
    /// @notice Initiates ownership transfer
    /// @dev Provides the current owner to transfer control to a new owner
    /// @param newOwner - Address of proposed new owner
    function transferOwnership(address newOwner) external onlyAdmin {
        require(newOwner != address(0), "Invalid owner address");
        pendingOwner = newOwner;
        emit OwnershipTransferInitiated(owner, newOwner);
    }
    /// @notice Initiates confirmation of transfer of ownership
    /// @dev Provides the new owner the ability to take control from the current owner
    function acceptOwnership() external {
        require(pendingOwner != address(0), "No pending owner");
        require(msg.sender == pendingOwner, "Not pending owner");
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }
    /// @notice Initiates completion of ownership transfer
    /// @dev Provides the current owner permanently transfer ownership to the new owner
    function renounceOwnership() external onlyAdmin {
        require(pendingOwner == address(0), "Pending owner exists");
        emit OwnershipRenounced(owner);
        owner = address(0);
    }
    /// @notice Emergency stop activation
    /// @dev Activates protection by disabling all contract functions
    /// @param reason - Reason for emergency stop (encoded in bytes32)
    function emergencyStop(bytes32 reason) external onlyAdmin {
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
    function liftEmergencyStop() external onlyAdmin {
        isEmergencyStopped = false;
        emergencyReason = "";
        if (!_wasPausedBeforeEmergency && paused()) {
            _unpause();
        }
        emit EmergencyStopLifted(msg.sender);
    }
    /// @notice Pauses contract operations
    function pause() external onlyRoot {
        require(!isEmergencyStopped, "Emergency stop active");
        _wasPausedBeforeEmergency = true;
        _pause();
    }
    /// @notice Unpauses contract operations
    function unpause() external onlyRoot {
        require(!isEmergencyStopped, "Emergency stop active");
        _wasPausedBeforeEmergency = false;
        _unpause();
    }
    /// @notice Transaction fee amount
    /// @dev Transaction fee amount, the value must be within the allowed range
    /// @param newFee - New fee value (in wei amount)
    function setTaxFee(uint256 newFee) external onlyAdmin {
        require(newFee >= minTaxFee && newFee <= maxTaxFee, "Invalid fee");
        taxFee = newFee;
        emit TaxFeeUpdated(newFee);
    }
    /// @notice Initiates withdrawal process
    /// @param amount - Amount to withdraw (in wei amount)
    /// @param isRoyalties - True for royalties, false for ETH
    function requestWithdrawal(
        uint256 amount,
        bool isRoyalties
    ) external onlyAdmin noActiveWithdrawalRequest {
        if (isRoyalties) {
            require(amount <= accumulatedRoyalties, "Insufficient royalties");
            withdrawalRequest = WithdrawalRequest({
                amount: amount,
                requestTime: block.timestamp,
                isCancelled: false,
                isRoyalties: true,
                availableEthBalance: 0,
                availableRoyaltiesBalance: accumulatedRoyalties
            });
        } else {
            uint256 availableBalance = address(this).balance -
                accumulatedRoyalties;
            require(amount <= availableBalance, "Insufficient ETH");
            withdrawalRequest = WithdrawalRequest({
                amount: amount,
                requestTime: block.timestamp,
                isCancelled: false,
                isRoyalties: false,
                availableEthBalance: availableBalance
            });
        }
        emit WithdrawalRequested(amount, block.timestamp);
    }
    /// @notice Initiates cancellation of a pending withdrawal
    function cancelWithdrawal() external onlyAdmin {
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
        onlyAdmin
        nonReentrant
        canWithdraw
        isNotCancelled
    {
        require(owner != address(0), "Owner not set");
        uint256 amount = withdrawalRequest.amount;
        bool isRoyalties = withdrawalRequest.isRoyalties;
        uint256 availableEthBalance = withdrawalRequest.availableEthBalance;
        uint256 availableRoyaltiesBalance = withdrawalRequest.availableRoyaltiesBalance;
        if (isRoyalties) {
        require(amount <= availableRoyaltiesBalance, "Insufficient royalties");
        accumulatedRoyalties -= amount;
        } else {
        uint256 currentAvailableBalance = address(this).balance - accumulatedRoyalties;
        require(currentAvailableBalance >= availableEthBalance, "ETH balance decreased");
        require(amount <= availableEthBalance, "Requested ETH exceeds available");
        }
        withdrawalRequest = WithdrawalRequest(0, 0, true, false, 0, 0);
        (bool success, ) = payable(owner).call{value: amount, gas: 50000}("");
        require(success, "Transfer failed");
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