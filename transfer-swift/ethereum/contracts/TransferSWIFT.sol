// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// @openzeppelin/contracts: Import libraries
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/// @title TransferSWIFT
/// @author Bogachenko Vyacheslav
/// @notice TransferSWIFT is a universal contract for batch transfers of native coins and tokens.
/// @custom:licence License: MIT
/// @custom:version Version 0.0.0.6 (unstable)

contract TransferSWIFT is ReentrancyGuard, Pausable, ERC165 {
    // Configuration data
    /// @notice Safe ETH operations
    using Address for address payable;
    /// @notice Contract owner address
    address public owner;
    /// @notice Transfer of ownership
    address public pendingOwner;
    /// @notice Protocol display name
    string public name = "TransferSWIFT";
    /// @notice Protocol symbol
    string public symbol = "SWIFT";
    /// @notice Current transaction fee (0.0001 ETH)
    uint256 public taxFee = 1e14;
    /// @notice Minimum allowed fee (0.000001 ETH)
    uint256 public minTaxFee = 1e12;
    /// @notice Maximum allowed fee (0.0005 ETH)
    uint256 public maxTaxFee = 5e14;
    /// @notice Accumulated protocol fees
    uint256 public accumulatedRoyalties;
    /// @notice Standard number of allowed recipients
    uint256 constant defaultRecipients = 15;
    /// @notice Maximum number of allowed recipients
    uint256 constant maxRecipients = 20;
    /// @notice Cooldown of rate limiting (5 minutes)
    uint256 public rateLimitDuration = 300;
    //// @notice The emergency stop flag of the contract
    bool public isEmergencyStopped;
    bool private _wasPausedBeforeEmergency;
    /// @notice The reason for activating the emergency mode
    string public emergencyReason;

    // Security mappings
    /// @notice Rate limiting
    mapping(address => uint256) public lastUsed;
    /// @notice Blacklisted addresses
    mapping(address => bool) public blacklist;
    /// @notice Addresses with extended recipient limits
    mapping(address => bool) public extendedRecipients;
    /// @notice Approved ERC20 tokens
    mapping(address => bool) public whitelistERC20;
    /// @notice Approved ERC721 tokens
    mapping(address => bool) public whitelistERC721;
    /// @notice Approved ERC1155 tokens
    mapping(address => bool) public whitelistERC1155;

    // Events
    /// @notice Ownership transfer event
    /// @dev Generates an event indicating successful transfer of ownership
    /// @param previousOwner Previous owner address
    /// @param newOwner New owner address
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    /// @notice Emergency mode activation event
    /// @param executor Activator's address
    /// @param reason Reason for activation
    event EmergencyStopActivated(address indexed executor, string reason);
    /// @notice Emergency mode deactivation event
    /// @param executor Deactivator address
    event EmergencyStopLifted(address indexed executor);
    // @notice Royalty withdrawal event
    // @dev Generates an event when the accumulated commissions have been successfully withdrawn
    // @param receiver Recipient address (always current owner)
    // @param amount Withdrawal amount in wei
    event RoyaltiesWithdrawn(address indexed receiver, uint256 amount);
    /// @notice funds withdrawal event
    /// @dev Generates an event when the accumulated funds have been successfully withdrawn
    /// @param receiver Recipient address (always current owner)
    /// @param amount Withdrawal amount in wei
    event FundsWithdrawn(address indexed receiver, uint256 amount);
    /// @notice Recipient limit change event
    /// @dev Allows an extended recipient limit for the specified user
    event MaxRecipientsSet(address indexed user, uint256 limit);
    /// @notice Recipient limit reset event
    /// @dev Restores the standard recipient limit for the specified user
    event DefaultRecipientsSet(address indexed user, uint256 limit);
    /// @notice Blacklist status change event
    /// @param user User's address
    /// @param status New status (true = added to blacklist/false = deleted from blacklist)
    event BlacklistUpdated(address indexed user, bool status);
    /// @notice Whitelist status change event
    /// @param user User's address
    /// @param status New status (true = added to whitelist/false = deleted from whitelist)
    event WhitelistERC20Updated(address indexed token, bool status);
    event WhitelistERC721Updated(address indexed token, bool status);
    event WhitelistERC1155Updated(address indexed token, bool status);

    // Modifiers
    /// @notice Restricts the function call to the owner
    /// @dev Checks if the sender's address matches the owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
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

    /// @notice Contract assembly
    /// @dev Sets msg.sender as the initial owner
    /// @dev Marked as payable to allow deployment with initial ETH balance
    constructor() payable {
        owner = msg.sender;
    }
    /// @dev Recipient function for incoming ETH transactions
    receive() external payable {}

    /// @notice Multitransfer for ETH (native coin)
    /// @dev Performs mass distribution of ETH (native coin) to several recipients
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
        require(recipients.length <= allowedRecipients, "Too many recipients");
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Recipient is zero address");
            require(!blacklist[recipients[i]], "Recipient blacklisted");
            require(amounts[i] > 0, "Amount must be greater than 0");
            uint256 oldTotal = totalAmount;
            totalAmount += amounts[i];
            require(totalAmount >= oldTotal, "Overflow detected");
        }
        require(msg.value >= totalAmount + taxFee, "Insufficient ETH");
        accumulatedRoyalties += taxFee;
        for (uint256 i = 0; i < recipients.length; i++) {
            payable(recipients[i]).sendValue(amounts[i]);
        }
        uint256 refund = msg.value - totalAmount - taxFee;
        if (refund > 0) {
            payable(msg.sender).sendValue(refund);
        }
    }
    /// @notice Multitransfer for ERC20 token standard
    /// @dev Performs mass distribution of ERC20 token to several recipients
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
        require(whitelistERC20[token], "Token not whitelisted");
        require(recipients.length == amounts.length, "Mismatched arrays");
        uint256 allowedRecipients = extendedRecipients[msg.sender]
            ? maxRecipients
            : defaultRecipients;
        require(recipients.length <= allowedRecipients, "Too many recipients");
        IERC20 erc20 = IERC20(token);
        accumulatedRoyalties += taxFee;
        require(msg.value == taxFee, "Incorrect tax fee");
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Recipient is zero address");
            require(!blacklist[recipients[i]], "Recipient blacklisted");
            require(amounts[i] > 0, "Amount must be greater than 0");
            (bool success, bytes memory data) = address(erc20).call(
                abi.encodeWithSelector(
                    erc20.transferFrom.selector,
                    msg.sender,
                    recipients[i],
                    amounts[i]
                )
            );
            require(
                success && (data.length == 0 || abi.decode(data, (bool))),
                "ERC20 transfer failed"
            );
        }
    }
    /// @notice Multitransfer for ERC721 token standard
    /// @dev Performs mass distribution of ERC721 token to several recipients
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
        require(whitelistERC721[token], "Token not whitelisted");
        require(recipients.length == tokenIds.length, "Mismatched arrays");
        uint256 allowedRecipients = extendedRecipients[msg.sender]
            ? maxRecipients
            : defaultRecipients;
        require(recipients.length <= allowedRecipients, "Too many recipients");
        IERC721 erc721 = IERC721(token);
        accumulatedRoyalties += taxFee;
        require(msg.value == taxFee, "Incorrect tax fee");
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Recipient is zero address");
            require(!blacklist[recipients[i]], "Recipient blacklisted");
            require(
                erc721.ownerOf(tokenIds[i]) == msg.sender,
                "Not owner of tokenId"
            );
            erc721.safeTransferFrom(msg.sender, recipients[i], tokenIds[i]);
        }
    }
    /// @notice Multitransfer for ERC1155 token standard
    /// @dev Performs mass distribution of ERC1155 token to several recipients
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
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Recipient is zero address");
            require(!blacklist[recipients[i]], "Recipient blacklisted");
            require(amounts[i] > 0, "Amount must be greater than 0");
            require(
                erc1155.balanceOf(msg.sender, ids[i]) >= amounts[i],
                "Not enough balance"
            );
            erc1155.safeTransferFrom(
                msg.sender,
                recipients[i],
                ids[i],
                amounts[i],
                ""
            );
        }
    }

    // Variables
    /// @notice Custom value of the rate limit
    /// @dev Establishing a custom time limit for accessing the contract
    function setRateLimit(uint256 newDuration) external onlyOwner {
        rateLimitDuration = newDuration;
    }
    /// @notice Custom extended recipient lists
    /// @dev Setting permissions from standard 15 on extended 20 positions
    function setMaxRecipients(address user) external onlyOwner {
        extendedRecipients[user] = true;
        emit MaxRecipientsSet(user, maxRecipients);
    }
    /// @notice Custom default recipient lists
    /// @dev Setting permissions from extended 20 on standard 15 positions
    function setDefaultRecipients(address user) external onlyOwner {
        extendedRecipients[user] = false;
        emit DefaultRecipientsSet(user, defaultRecipients);
    }
    /// @notice Formation of the blacklist
    /// @dev Adding an address to the blacklist
    function addBlacklist(address user) external onlyOwner {
        blacklist[user] = true;
        emit BlacklistUpdated(user, true);
    }
    /// @notice Abolition of the blacklist
    /// @dev Removing an address from the blacklist
    function delBlacklist(address user) external onlyOwner {
        blacklist[user] = false;
        emit BlacklistUpdated(user, false);
    }
    /// @notice Formation of the whitelist for ERC20 token standard
    /// @dev Adding an address to the whitelist for ERC20 token standard
    function addWhitelistERC20(address token) external onlyOwner {
        whitelistERC20[token] = true;
        emit WhitelistERC20Updated(token, true);
    }
    /// @notice Abolition of the whitelist for ERC20 token standard
    /// @dev Removing an address from the whitelist for ERC20 token standard
    function delWhitelistERC20(address token) external onlyOwner {
        whitelistERC20[token] = false;
        emit WhitelistERC20Updated(token, false);
    }
    /// @notice Formation of the whitelist for ERC721 token standard
    /// @dev Adding an address to the whitelist for ERC721 token standard
    function addWhitelistERC721(address token) external onlyOwner {
        whitelistERC721[token] = true;
        emit WhitelistERC721Updated(token, true);
    }
    /// @notice Abolition of the whitelist for ERC721 token standard
    /// dev Removing an address from the whitelist for ERC721 token standard
    function delWhitelistERC721(address token) external onlyOwner {
        whitelistERC721[token] = false;
        emit WhitelistERC721Updated(token, false);
    }
    /// @notice Formation of the whitelist for ERC1155 token standard
    /// @dev Adding an address to the whitelist for ERC1155 token standard
    function addWhitelistERC1155(address token) external onlyOwner {
        whitelistERC1155[token] = true;
        emit WhitelistERC1155Updated(token, true);
    }
    /// @notice Abolition of the whitelist for ERC1155 token standard
    /// @dev Removing an address from the whitelist for ERC1155 token standard
    function delWhitelistERC1155(address token) external onlyOwner {
        whitelistERC1155[token] = false;
        emit WhitelistERC1155Updated(token, false);
    }
    /// @notice Initiates a two-step ownership transfer process
    /// @dev Sets the pending owner address which can later claim ownership
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner address");
        pendingOwner = newOwner;
    }
    /// @notice Completes ownership transfer process
    /// @dev Allows pending owner to finalize the ownership transfer
    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "Not pending owner");
        emit OwnershipTransferred(owner, msg.sender);
        owner = msg.sender;
        pendingOwner = address(0);
    }
    /// @notice Permanently renounces contract ownership
    /// @dev Sets the contract owner to address zero
    function renounceOwnership() external onlyOwner {
        pendingOwner = address(0);
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }
    /// @notice Activates contract emergency stop
    function emergencyStop(string calldata reason) external onlyOwner {
        require(bytes(reason).length <= 32, "Reason too long");
        _wasPausedBeforeEmergency = paused();
        isEmergencyStopped = true;
        emergencyReason = reason;
        if (!_wasPausedBeforeEmergency) {
            _pause();
        }
        emit EmergencyStopActivated(msg.sender, reason);
    }
    /// @notice Removes emergency stop
    function liftEmergencyStop() external onlyOwner {
        isEmergencyStopped = false;
        emergencyReason = "";
        if (!_wasPausedBeforeEmergency && paused()) {
            _unpause();
        }
        emit EmergencyStopLifted(msg.sender);
    }
    /// @notice Establishing the transaction fee amount
    /// @dev The new fee must be within predefined min/max bounds
    function setTaxFee(uint256 newFee) external onlyOwner {
        require(newFee >= minTaxFee && newFee <= maxTaxFee, "Invalid fee");
        taxFee = newFee;
    }
    /// @notice Withdraws accumulated royalty fees to owner
    /// @dev Withdraws commission funds only
    function withdrawRoyalties() external onlyOwner nonReentrant {
        uint256 amount = accumulatedRoyalties;
        require(amount > 0, "No royalties");
        require(owner != address(0), "Owner address not set");
        accumulatedRoyalties = 0;
        (bool success, ) = payable(owner).call{value: amount, gas: 2300}("");
        require(success, "ETH transfer failed");
        emit RoyaltiesWithdrawn(owner, amount);
    }
    /// @notice Withdraws accumulated funds to owner
    /// @dev Withdraws funds only
    function withdrawFunds() external onlyOwner nonReentrant {
        uint256 availableBalance = address(this).balance - accumulatedRoyalties;
        require(availableBalance > 0, "No available funds");
        payable(owner).sendValue(availableBalance);
        emit FundsWithdrawn(owner, availableBalance);
    }
    /// @notice Pauses the contract
    function pause() external onlyOwner {
        if (!isEmergencyStopped) {
            _wasPausedBeforeEmergency = true;
        }
        _pause();
    }
    /// @notice Unpauses the contract
    function unpause() external onlyOwner {
        if (!isEmergencyStopped) {
            _wasPausedBeforeEmergency = false;
            _unpause();
        }
    }
    /// @notice ERC165 interface support check
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC20).interfaceId ||
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC1155).interfaceId ||
            interfaceId == type(ERC165).interfaceId;
    }
}