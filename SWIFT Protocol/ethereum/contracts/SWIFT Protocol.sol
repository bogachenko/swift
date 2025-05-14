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
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

/// @title SWIFT Protocol
/// @author Bogachenko Vyacheslav
/// @notice SWIFT Protocol is a universal contract for batch transfers of native coins and tokens.
/// @custom:licence License: MIT
/// @custom:version Version 0.0.0.9 (unstable)

contract SWIFTProtocol is AccessControlEnumerable, ReentrancyGuard, Pausable {
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
    /// @dev Security delay of 1 day (or 86400 seconds)
    uint256 public constant withdrawalDelay = 86400 seconds;
    /// @notice Withdrawal types
    /// @dev Define named constants at the contract level
    /// - 0x6973526f79616c74696573 ("isRoyalties"): Protocol royalties withdrawal
    /// - 0x6973455448 ("isETH"): Native ETH withdrawal
    /// - 0x69734552433230 ("isERC20"): ERC20 token withdrawal
    /// - 0x6973455243373231 ("isERC721"): ERC721 NFT withdrawal
    /// - 0x697345524331313535 ("isERC1155"): ERC1155 token withdrawal
    bytes32 public constant withdrawalTypeRoyalties = "isRoyalties";
    bytes32 public constant withdrawalTypeETH = "isETH";
    bytes32 public constant withdrawalTypeERC20 = "isERC20";
    bytes32 public constant withdrawalTypeERC721 = "isERC721";
    bytes32 public constant withdrawalTypeERC1155 = "isERC1155";
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
    string public name = "SWIFT Protocol";
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
    /// @notice MEV protection
    /// @dev When true, transactions will use a commit-reveal pattern
    bool public mevProtectionEnabled = false;
    /// @notice Time window for executing a committed transaction
    /// @dev Default: 10 minutes (600 seconds)
    uint256 public commitmentWindow = 600;

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
    /// @notice Whitelist registry for approved token contracts
    /// @dev Nested mapping tracking allowed tokens per standard
    /// @param standard - The token standard (ERC20/ERC721/ERC1155)
    /// @param token - The token contract address to check
    /// @return bool - True if token is whitelisted for its standard
    mapping(TokenWhitelist => mapping(address => bool)) public whitelist;
    /// @notice Mapping to store transaction commitments
    /// @dev Maps commitment hash to its timestamp
    mapping(bytes32 => uint256) public pendingCommitments;

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
        bytes32 withdrawalType;
        address tokenAddress;
        uint256 tokenId;
        uint256 availableEthBalance;
        uint256 availableRoyaltiesBalance;
    }

    /*********************************************************************/
    /// @title Contains the necessary data to process requests in the contract
    /// @notice Implements security measures using templates
    /*********************************************************************/
    /// @notice Whitelist token enumeration
    /// @dev Classification of whitelisted tokens
    enum TokenWhitelist {
        ERC20,
        ERC721,
        ERC1155
    }
    /// @notice Multitransfer token enumeration
    /// @dev Classification of all tokens
    enum TransferType {
        ETH,
        ERC20,
        ERC721,
        ERC1155
    }

    /*********************************************************************/
    /// @title Contract lifecycle events
    /// @notice Events related to contract configuration changes
    /*********************************************************************/
    /// @notice Emitted when ownership transfer is completed
    /// @dev Logs both previous and new contract owners
    /// @param previousOwner - Address of the outgoing owner
    /// @param newOwner - Address of the new owner
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    /// @notice Emitted when ownership transfer is initiated
    /// @dev Marks the beginning of a two-step ownership transfer process
    /// @param currentOwner - Address of the current owner
    /// @param pendingOwner - Address of the pending new owner
    event OwnershipTransferInitiated(address indexed currentOwner, address indexed pendingOwner);
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
    /// @notice Emitted when a token's whitelist status changes
    /// @dev Controls allowed tokens for operations
    /// @param standard Token standard category
    /// @param token - Token contract address
    /// @param status - New whitelist status (true = added, false = removed)
    event WhitelistUpdated(TokenWhitelist indexed standard, address indexed token, bool status);
    /// @notice Emitted when the transaction fee is updated
    /// @dev Signals a change in the protocol's tax fee percentage
    /// @param newFee - New fee value in wei
    event TaxFeeUpdated(uint256 indexed newFee);
    /// @notice Emitted when the number allowed recipients per transaction is updated
    /// @dev Indicates a change in the batch operation recipient capacity
    /// @param newLimit - The new maximum number of recipients allowed
    event RecipientLimitUpdated(uint256 indexed newLimit);
    /// @notice Emitted when a token transfer operation fails
    /// @dev Provides detailed failure context for diagnostics
    /// @param token - Address of token contract
    /// @param from - Initiating address
    /// @param to - Recipient address
    /// @param tokenId - Token ID (for ERC721/ERC1155)
    /// @param reason - Failure reason string or error code
    event TokenTransferFailed(address token, address from, address to, uint256 tokenId, string reason);
    /// @notice Emitted when a token transfer succeeds
    /// @param token - Address of token contract
    /// @param from - Initiating address
    /// @param to - Recipient address
    /// @param tokenId - Transferred token ID
    event TokenTransferSucceeded(address token, address from, address to, uint256 tokenId);
    /// @notice Emitted when a transaction commitment is created
    /// @param committer - Address that created the commitment
    /// @param commitmentHash - Hash of the committed transaction
    /// @param timestamp - Block timestamp when commitment was created
    event TransactionCommitted(address indexed committer, bytes32 indexed commitmentHash, uint256 timestamp);
    /// @notice Emitted when MEV protection setting is changed
    /// @param enabled - New state of MEV protection
    /// @param changedBy - Address that changed the setting
    event MevProtectionSettingChanged(bool enabled, address indexed changedBy);
    /// @notice Emitted when commitment window duration is updated
    /// @param newWindow - New commitment window duration in seconds
    /// @param changedBy - Address that changed the setting
    event CommitmentWindowUpdated(uint256 newWindow, address indexed changedBy);
    /// @notice Emitted when a valid commitment is consumed
    /// @dev Indicates successful use of MEV protection mechanism
    /// @param user - Address that used the commitment
    /// @param commitmentHash - The consumed commitment hash (indexed)
    /// @param timestamp - Block timestamp of commitment usage
    event CommitmentUsed(address indexed user, bytes32 indexed commitmentHash, uint256 timestamp);

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
        require(hasRole(adminRole, msg.sender) || hasRole(modRole, msg.sender), "Caller is not admin or mod");
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
        require(block.timestamp >= lastUsed[msg.sender] + rateLimitDuration, "Rate limit: Wait cooldown period");
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
        require(withdrawalRequest.requestTime == 0 || withdrawalRequest.isCancelled, "Active withdrawal request exists.");
        _;
    }
    /// @notice Withdrawal timelock period
    /// @dev Enforces withdrawal time lock period
    modifier canWithdraw() {
        require(block.timestamp >= withdrawalRequest.requestTime + withdrawalDelay, "The locking period has not expired yet");
        _;
    }
    /// @notice Withdrawal request cancel
    /// @dev Ensures request wasn't cancelled
    modifier isNotCancelled() {
        require(!withdrawalRequest.isCancelled, "Withdrawal request is cancelled");
        _;
    }
    /// @notice Validates basic requirements for batch transfers
    /// @param recipients - Array of recipient addresses
    /// @param dataLength - Length of the data array (amounts or tokenIds)
    function _validateBatchTransfer(address[] calldata recipients, uint256 dataLength) internal view {
    require(recipients.length == dataLength, "Mismatched arrays");
    require(recipients.length > 0, "Empty recipient array");
    uint256 allowedRecipients = extendedRecipients[msg.sender]
        ? maxRecipients
        : currentRecipients;
    require(recipients.length <= allowedRecipients, "Too many recipients");
    }

    /*********************************************************************/
    /// @title Core Contract Functions
    /// @notice Base contract setup and fallback handlers
    /*********************************************************************/
    /// @notice Initializes contract
    /// @dev Sets `msg.sender` as initial owner address
    /// @dev Marked payable to enable ETH funding during deployment (the contract gets 1 wei when deployed)
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
    /// @notice Multitransfer
    /// @dev Batch transfers to multiple recipients
    /// @param transferType - Type of transfer (0: ETH, 1: ERC20, 2: ERC721, 3: ERC1155)
    /// @param token - Address of token contract (required for ERC20/ERC721/ERC1155)
    /// @param recipients - Array of recipient addresses
    /// @param values - For ETH/ERC20: amounts, for ERC721: token IDs, for ERC1155: token IDs
    /// @param amounts - For ERC1155 only: quantities of each token to transfer
    /// @param useMevProtection - Whether to enable MEV protection mechanisms
    /// @param salt - Unique salt for commitment hash generation
    function multiTransfer(
        TransferType transferType,
        address token,
        address[] calldata recipients,
        uint256[] calldata values,
        uint256[] calldata amounts, 
        bool useMevProtection,
        bytes32 salt
    )
        external
        payable
        nonReentrant
        enforceRateLimit
        whenNotPaused
        emergencyNotActive
        notBlacklisted(msg.sender)
    {
       _validateBatchTransfer(recipients, values.length);
        if (transferType == TransferType.ERC20) {
        require(token != address(0), "Token address required");
        require(whitelist[TokenWhitelist.ERC20][token], "Token not whitelisted");
    } else if (transferType == TransferType.ERC721) {
        require(token != address(0), "Token address required");
        require(whitelist[TokenWhitelist.ERC721][token], "Token not whitelisted");
    } else if (transferType == TransferType.ERC1155) {
        require(token != address(0), "Token address required");
        require(whitelist[TokenWhitelist.ERC1155][token], "Token not whitelisted");
    }
        bytes32 commitmentHash;
        if (transferType == TransferType.ETH || transferType == TransferType.ERC20) {
            commitmentHash = transferType == TransferType.ETH
                ? getEthCommitmentHash(msg.sender, recipients, values, salt)
                : getTokenCommitmentHash(msg.sender, token, recipients, abi.encode(values), salt);
        } else if (transferType == TransferType.ERC721) {
            commitmentHash = getTokenCommitmentHash(msg.sender, token, recipients, abi.encode(values), salt);
        } else if (transferType == TransferType.ERC1155) {
            require(amounts.length == values.length, "Mismatched tokenIds and amounts");
            bytes memory packedData = abi.encode(
                keccak256(abi.encode(values)),
                keccak256(abi.encode(amounts))
            );
            commitmentHash = getTokenCommitmentHash(msg.sender, token, recipients, packedData, salt);
        } else {
            revert("Unsupported transfer type");
        }
        if (useMevProtection) {
            require(validateCommitment(commitmentHash), "Invalid commitment");
        clearCommitment(commitmentHash);
        }
        if (transferType == TransferType.ETH) {
            _transferETH(recipients, values);
        } else if (transferType == TransferType.ERC20) {
            _transferERC20(token, recipients, values);
        } else if (transferType == TransferType.ERC721) {
            _transferERC721(token, recipients, values);
        } else if (transferType == TransferType.ERC1155) {
            _transferERC1155(token, recipients, values, amounts);
        }
    }
    /// @notice Multitransfer ETH
    /// @dev Batch transfers ETH to multiple recipients
    /// @param recipients - Array of recipient addresses
    /// @param amounts - Array of transfer amounts
    function _transferETH(address[] calldata recipients, uint256[] calldata amounts) internal nonReentrant {
        uint256 totalAmount;
        for (uint256 i = 0; i < recipients.length; ) {
            address recipient = recipients[i];
            uint256 amount = amounts[i];
            validateRecipient(recipient);
            require(amount > 0, "Zero amount");
            totalAmount += amount;
            unchecked { ++i; }
        }
        uint256 totalFee = taxFee * recipients.length;
        require(msg.value >= totalAmount + totalFee, "Insufficient ETH");
        accumulatedRoyalties += totalFee;
        for (uint256 i = 0; i < recipients.length; ) {
            (bool success, ) = payable(recipients[i]).call{value: amounts[i]}("");
            require(success, "ETH transfer failed");
            unchecked { ++i; }
        }
        uint256 refund = msg.value - totalAmount - totalFee;
        if (refund > 0) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: refund}("");
            require(refundSuccess, "Refund failed");
        }
    }
    /// @notice Multitransfer ERC20
    /// @dev Batch transfers ERC20 to multiple recipients
    /// @param token - Address of ERC20 token contract
    /// @param recipients - Array of valid recipient addresses
    /// @param amounts - Array of transfer amounts
    function _transferERC20(address token, address[] calldata recipients, uint256[] calldata amounts) internal nonReentrant {
        IERC20 erc20 = IERC20(token);
        uint256 totalFee = collectTaxFee(recipients.length);
        require(msg.value == totalFee, "Incorrect fee");
        for (uint256 i = 0; i < recipients.length; ) {
            address to = recipients[i];
            uint256 amt = amounts[i];
            validateRecipient(to);
            require(amt > 0, "Amount must be > 0");
            SafeERC20.safeTransferFrom(erc20, msg.sender, to, amt);
            unchecked { ++i; }
        }
    }
    /// @notice Multitransfer ERC721
    /// @dev Batch transfers ERC721 to multiple recipients
    /// @param token - Address of ERC721 token contract
    /// @param recipients - Array of valid recipient addresses
    /// @param tokenIds - Array of ERC721 token IDs
    function _transferERC721(address token, address[] calldata recipients, uint256[] calldata tokenIds) internal nonReentrant {
        IERC721 erc721 = IERC721(token);
        uint256 totalFee = collectTaxFee(recipients.length);
        require(msg.value == totalFee, "Incorrect fee");
        for (uint256 i = 0; i < recipients.length; ) {
            address to = recipients[i];
            uint256 id = tokenIds[i];
            validateRecipient(to);
            try erc721.safeTransferFrom(msg.sender, to, id, "") {
                emit TokenTransferSucceeded(token, msg.sender, to, id);
            } catch Error(string memory reason) {
                emit TokenTransferFailed(token, msg.sender, to, id, reason);
                revert(string(abi.encode("ERC721 transfer failed: ", reason)));
            } catch {
                emit TokenTransferFailed(token, msg.sender, to, id, "unknown error");
                revert("ERC721 transfer failed with unknown error");
            }
            unchecked { ++i; }
        }
    }
    /// @notice Multitransfer ERC1155
    /// @dev Batch transfers ERC1155 to multiple recipients
    /// @param token - ERC1155 contract address
    /// @param recipients - Array of valid recipient addresses
    /// @param amounts - Array of transfer amounts
    /// @param ids - Array of ERC1155 token IDs
    function _transferERC1155(address token, address[] calldata recipients, uint256[] calldata ids, uint256[] calldata amounts ) internal nonReentrant {
        IERC1155 erc1155 = IERC1155(token);
        uint256 totalFee = collectTaxFee(recipients.length);
        require(msg.value == totalFee, "Incorrect fee");
        for (uint256 i = 0; i < recipients.length; ) {
            address to = recipients[i];
            uint256 id = ids[i];
            uint256 amt = amounts[i];
            validateRecipient(to);
            require(erc1155.balanceOf(msg.sender, id) >= amt, "Not enough balance");
            require(amt > 0, "Amount must be > 0");
            try erc1155.safeTransferFrom(msg.sender, to, id, amt, "") {
                emit TokenTransferSucceeded(token, msg.sender, to, id);
            } catch Error(string memory reason) {
                emit TokenTransferFailed(token, msg.sender, to, id, reason);
                revert(string(abi.encode("ERC1155 transfer failed: ", reason)));
            } catch {
                emit TokenTransferFailed(token, msg.sender, to, id, "unknown error");
                revert("ERC1155 transfer failed with unknown error");
            }
            unchecked { ++i; }
        }
    }
    /// @notice Grants a specific role to an address
    /// @dev Includes additional safeguards for role capacity limits
    /// @param role - The role identifier to grant (bytes32)
    /// @param account - The address receiving the role
    function grantRole(bytes32 role, address account) public override(AccessControl, IAccessControl) onlyAdmin emergencyNotActive {
        require(hasRole(adminRole, msg.sender), "Caller is not admin");
        require(account != address(0), "Cannot grant role to zero address");
        require(!isContract(account), "Cannot grant role to a contract");
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
    function revokeRole(bytes32 role, address account) public override(AccessControl, IAccessControl) onlyAdmin emergencyNotActive {
        require(hasRole(adminRole, msg.sender), "Caller is not admin");
        if (role == adminRole) {
            require(getRoleMemberCount(adminRole) > 1, "Cannot remove last admin");
            require(account != msg.sender, "Self-removal forbidden");
        }
        _revokeRole(role, account);
        emit RoleRevoked(role, account, msg.sender);
    }
    /// @notice Toggles MEV protection for the caller's transactions
    /// @dev Allows users to enable/disable MEV protection for their transactions
    /// @param enabled - True to enable MEV protection, false to disable
    function setMevProtection(bool enabled) external {
        mevProtectionEnabled = enabled;
        emit MevProtectionSettingChanged(enabled, msg.sender);
    }
    /// @notice Updates the commitment window duration
    /// @param newWindow - New commitment window duration in seconds
    function updateCommitmentWindow(uint256 newWindow) external onlyAdmin {
        require(newWindow >= 60 && newWindow <= 3600, "Window must be between 1-60 minutes");
        commitmentWindow = newWindow;
        emit CommitmentWindowUpdated(newWindow, msg.sender);
    }
    /// @notice Creates a commitment for a future transaction
    /// @dev First step in the commit-reveal pattern for MEV protection
    /// @param commitmentHash - Hash of the transaction details
    function commitTransaction(bytes32 commitmentHash) external {
        require(commitmentHash != bytes32(0), "Invalid commitment hash");
        pendingCommitments[commitmentHash] = (block.timestamp << 160) | uint256(uint160(msg.sender));
        emit TransactionCommitted(msg.sender, commitmentHash, block.timestamp);
    }
    /// @notice Validates a transaction commitment
    /// @dev Checks if commitment exists and is within the time window
    /// @dev packedData layout: [commitTime (upper 96 bits) | committer (lower 160 bits)]
    /// @param commitmentHash - Hash to validate
    function validateCommitment(bytes32 commitmentHash) internal view returns (bool) {
        uint256 packedData = pendingCommitments[commitmentHash];
        if (packedData == 0) return false;
        uint256 commitTime = packedData >> 160;
        address committer = address(uint160(packedData & ((1 << 160) - 1)));
        return (block.timestamp >= commitTime && block.timestamp <= commitTime + commitmentWindow && committer == msg.sender);
    }
    /// @notice Clears a used commitment
    /// @dev Should be called after a commitment is used
    /// @param commitmentHash - Hash to clear
    function clearCommitment(bytes32 commitmentHash) internal {
        uint256 packedData = pendingCommitments[commitmentHash];
        require(packedData != 0, "No such commitment");
        address committer = address(uint160(packedData & ((1 << 160) - 1)));
        require(msg.sender == committer, "Not committer");
        delete pendingCommitments[commitmentHash];
    }
    /// @notice Generates a commitment hash for ETH transfers
    /// @dev Used to create consistent hashes for commit-reveal pattern
    /// @param sender - Transaction sender
    /// @param recipients - Array of recipient addresses
    /// @param amounts - Array of transfer amounts
    /// @param salt - Random value to prevent hash prediction
    function getEthCommitmentHash(address sender, address[] calldata recipients, uint256[] calldata amounts, bytes32 salt) public pure returns (bytes32) {
        return keccak256(abi.encode(keccak256(abi.encode(sender)), keccak256(abi.encode(recipients)), keccak256(abi.encode(amounts)), salt));
    }
    /// @notice Generates a commitment hash for token transfers
    /// @dev Used for ERC20/721/1155 transfers
    /// @param sender - Transaction sender
    /// @param token - Token contract address
    /// @param recipients - Array of recipient addresses
    /// @param tokenData - Additional token data (amounts or IDs)
    /// @param salt - Random value to prevent hash prediction
    function getTokenCommitmentHash(address sender, address token, address[] calldata recipients, bytes memory tokenData, bytes32 salt) public pure returns (bytes32) {
        return keccak256(abi.encode(keccak256(abi.encode(sender)), keccak256(abi.encode(token)), keccak256(abi.encode(recipients)), keccak256(tokenData), salt));
    }
    /// @notice Handles MEV protection validation
    /// @param useMevProtection - Whether to use MEV protection
    /// @param commitmentHash - Hash of the transaction details
    /// @return Whether the commitment is valid and should be processed
    function handleMevProtection(bool useMevProtection, bytes32 commitmentHash) internal returns (bool) {
        if (useMevProtection) {
            require(validateCommitment(commitmentHash), "Invalid or expired commitment");
            clearCommitment(commitmentHash);
            emit CommitmentUsed(msg.sender, commitmentHash, block.timestamp);
        }
        return true;
    }
    /// @notice Validates recipient address
    /// @param recipient - Address to validate
    /// @return Whether the address is valid
    function validateRecipient(address recipient) internal view returns (bool) {
        require(recipient != address(0), "Zero address recipient");
        require(recipient != address(this), "Cannot send to contract itself");
        require(!blacklist[recipient], "Blacklisted recipient");
        return true;
    }
    /// @notice Validates and collects the tax fee
    /// @param recipientCount - Number of recipients
    function collectTaxFee(uint256 recipientCount) internal returns (uint256) {
        uint256 totalFee = taxFee * recipientCount;
        require(msg.value >= totalFee, "Insufficient fee amount");
        accumulatedRoyalties += totalFee;
        return totalFee;
    }
    /// @notice Transaction ratelimit
    /// @dev Sets transaction rate limit duration
    /// @param newDuration - New cooldown period in seconds
    function setRateLimit(uint256 newDuration) external onlyRoot {
        require(newDuration >= 10 && newDuration <= 3600, "Rate limit must be reasonable");
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
    function updateRecipientLimit(uint256 newLimit) external onlyRoot {
        require(newLimit >= defaultRecipients && newLimit <= maxRecipients, "Limit out of bounds");
        currentRecipients = newLimit;
        emit RecipientLimitUpdated(newLimit);
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
    /// @dev Functions for managing restricted addresses
    /// @param users - Array of addresses to update
    /// @param status - New blacklist status (true = add, false = remove)
    function updateBlacklist(address[] calldata users, bool status) external onlyRoot {
        uint256 len = users.length;
        require(len > 0, "Empty list");
        require(len <= 100, "Too many addresses");
        for (uint256 i; i < len; ) {
            address user = users[i];
            require(user != address(0), "Zero address");
            if (status) {
                require(!blacklist[user], "Already blacklisted");
            } else {
                require(blacklist[user], "Not in blacklist");
            }
            blacklist[user] = status;
            emit BlacklistUpdated(user, status);
            unchecked { ++i; }
        }
    }
    /// @notice Whitelist management
    /// @dev Functions for managing approved token contracts
    /// @param standard - Token standard to update (ERC20/ERC721/ERC1155)
    /// @param tokens - Array of token contract addresses
    /// @param status - New whitelist status (true = add, false = remove)
    function updateWhitelist(TokenWhitelist standard, address[] calldata tokens, bool status) external onlyRoot {
        uint256 len = tokens.length;
        require(len > 0, "No tokens");
        require(len <= 100, "Too many addresses");
        for (uint256 i; i < len; ) {
            address token = tokens[i];
            require(isContract(token), "Not a contract");
            if (!status) {
                require(whitelist[standard][token], "Not in whitelist");
            }
            whitelist[standard][token] = status;
            emit WhitelistUpdated(standard, token, status);
            unchecked { ++i; }
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
    /// @notice Withdrawal request
    /// @dev Supports multiple asset types through `withdrawalType` parameter
    /// @param amount - Withdrawal amount
    /// @param withdrawalType - Withdrawal category identifier
    /// @param tokenAddress - Token contract address (required for ERC20/ERC721/ERC1155)
    /// @param tokenId - Token ID (required for ERC721/ERC1155)
        function requestWithdrawal(uint256 amount, bytes32 withdrawalType, address tokenAddress, uint256 tokenId) external onlyAdmin noActiveWithdrawalRequest {
        require(withdrawalRequest.requestTime == 0 || withdrawalRequest.isCancelled || block.timestamp > withdrawalRequest.requestTime + 7 days, "Active withdrawal request exists");
        WithdrawalRequest memory newRequest = WithdrawalRequest({
            amount: amount,
            requestTime: block.timestamp,
            isCancelled: false,
            withdrawalType: withdrawalType,
            tokenAddress: address(0),
            tokenId: 0,
            availableEthBalance: 0,
            availableRoyaltiesBalance: 0
        });
        if (withdrawalType == withdrawalTypeRoyalties) {
            require(amount > 0 && amount <= accumulatedRoyalties, "Invalid royalties");
            newRequest.availableRoyaltiesBalance = accumulatedRoyalties;
        } else if (withdrawalType == withdrawalTypeETH) {
            uint256 availableEthBalance = address(this).balance - accumulatedRoyalties;
            require(amount > 0 && amount <= availableEthBalance, "Invalid ETH");
            newRequest.availableEthBalance = availableEthBalance;
        } else if (withdrawalType == withdrawalTypeERC20) {
            require(tokenAddress != address(0), "Token address required");
            uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
            require(amount > 0 && amount <= balance, "Invalid ERC20 amount");
            newRequest.tokenAddress = tokenAddress;
        } else if (withdrawalType == withdrawalTypeERC721) {
            require(tokenAddress != address(0), "Token address required");
            require(amount == 1, "ERC721 amount must be 1");
            require(IERC721(tokenAddress).ownerOf(tokenId) == address(this), "ERC721 not owned");
            newRequest.amount = 1; 
            newRequest.tokenAddress = tokenAddress;
            newRequest.tokenId = tokenId;
        } else if (withdrawalType == withdrawalTypeERC1155) {
            require(tokenAddress != address(0), "Token address required");
            uint256 balance = IERC1155(tokenAddress).balanceOf(address(this), tokenId);
            require(amount > 0 && amount <= balance, "Invalid ERC1155 amount");
            newRequest.tokenAddress = tokenAddress;
            newRequest.tokenId = tokenId;
        } else {
            revert("Unsupported withdrawal type");
        }
        withdrawalRequest = newRequest;
        emit WithdrawalRequested(amount, block.timestamp);
    }
    /// @notice Initiates cancellation of a pending withdrawal
    function cancelWithdrawal() external onlyAdmin {
        require(withdrawalRequest.requestTime > 0, "No withdrawal request exists");
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
        WithdrawalRequest memory request = withdrawalRequest;
        uint256 amount = request.amount;
        bytes32 wType = request.withdrawalType;
        address token = request.tokenAddress;
        uint256 id = request.tokenId;
        bool success;
        if (wType == withdrawalTypeRoyalties || wType == withdrawalTypeETH) {
            uint256 available = wType == withdrawalTypeRoyalties 
                ? request.availableRoyaltiesBalance 
                : (address(this).balance - accumulatedRoyalties);
            if(wType == withdrawalTypeETH) {
                require(available >= request.availableEthBalance, "ETH balance reduced");
                require(amount <= request.availableEthBalance, "ETH over requested");
            } else {
                require(amount <= available, "Royalties reduced");
            }
            if(wType == withdrawalTypeRoyalties) {
                accumulatedRoyalties -= amount;
            }
            withdrawalRequest = WithdrawalRequest(0, 0, true, "", address(0), 0, 0, 0);
            (success, ) = payable(owner).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else if (wType == withdrawalTypeERC20 || wType == withdrawalTypeERC1155) {
            uint256 balance = wType == withdrawalTypeERC20 
                ? IERC20(token).balanceOf(address(this)) 
                : IERC1155(token).balanceOf(address(this), id);
            require(amount <= balance, wType == withdrawalTypeERC20 
                ? "ERC20 insufficient" 
                : "ERC1155 insufficient");
            if(wType == withdrawalTypeERC20) {
                SafeERC20.safeTransfer(IERC20(token), owner, amount);
            } else {
                IERC1155(token).safeTransferFrom(address(this), owner, id, amount, "");
            }
                withdrawalRequest = WithdrawalRequest(0, 0, true, "", address(0), 0, 0, 0);
        } else if (wType == withdrawalTypeERC721) {
            require(IERC721(token).ownerOf(id) == address(this), "Not owner of ERC721");
                IERC721(token).safeTransferFrom(address(this), owner, id);
                withdrawalRequest = WithdrawalRequest(0, 0, true, "", address(0), 0, 0, 0);
        } else {
            revert("Unsupported withdrawal type");
        }
        emit WithdrawalCompleted(amount);
    }
    /// @notice Interfaces support
    /// @dev Low-level query to check supported interfaces
    /// @return - Returns True for supported interfaces (IERC20, IERC721, IERC1155).
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            super.supportsInterface(interfaceId) ||
            interfaceId == type(IERC20).interfaceId ||
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC1155).interfaceId;
    }
}