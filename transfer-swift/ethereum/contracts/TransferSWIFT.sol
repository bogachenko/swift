// TransferSWIFT <https://github.com/bogachenko/swift>
// License: MIT
// Version 0.0.0.2 (stable)

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract TransferSWIFT is Ownable, Pausable, ReentrancyGuard, IERC165 {
    using SafeERC20 for IERC20;
    using Address for address;

    string public constant name = "TransferSWIFT";
    string public constant symbol = "SWIFT";

    uint256 public constant CheckTaxFee = 1e14; // 0.0001 ETH
    uint256 public taxFee = CheckTaxFee;

    uint256 public defaultMaxRecipients = 15;
    mapping(address => bool) public maxRecipientsOverride;

    mapping(address => uint256) public lastUsed;
    uint256 public rateLimitInterval = 1 minutes;

    mapping(address => bool) public blacklist;
    mapping(address => bool) public whitelistERC20;
    mapping(address => bool) public whitelistERC721;
    mapping(address => bool) public whitelistERC1155;

    mapping(bytes32 => bool) private usedNonces;

    uint256 public constant gasLimitGlobal = 30000000;
    uint256 public gasLimitEth = 26000;
    uint256 public gasLimitErc20 = 70000;
    uint256 public gasLimitErc721 = 105000;
    uint256 public gasLimitErc1155 = 72000;

    event MultiTransfer(
        address indexed sender,
        uint256 ethCount,
        uint256 erc20Count,
        uint256 erc721Count,
        uint256 erc1155Count,
        bytes32 nonce
    );
    event TaxFeeChanged(uint256 oldFee, uint256 newFee);
    event MaxRecipientsGranted(address indexed account);
    event RateLimitIntervalChanged(uint256 oldInterval, uint256 newInterval);
    event BlacklistAdded(address indexed account);
    event BlacklistRemoved(address indexed account);
    event WhitelistERC20Added(address indexed token);
    event WhitelistERC20Removed(address indexed token);
    event WhitelistERC721Added(address indexed token);
    event WhitelistERC721Removed(address indexed token);
    event WhitelistERC1155Added(address indexed token);
    event WhitelistERC1155Removed(address indexed token);
    event Rescue(address indexed to, uint256 amount);
    event NonceUsed(bytes32 indexed nonce);
    event GasLimitTooHigh(string limitType);
    event OnlyPausedWithdrawAllowed();

    modifier notBlacklisted(address account) {
        require(!blacklist[account], "Address blacklisted");
        _;
    }

    constructor() payable Ownable(msg.sender) {}

    function supportsInterface(
        bytes4 interfaceId
    ) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
    // Owner functions
    function setTaxFee(uint256 _newFee) external onlyOwner {
        require(_newFee >= CheckTaxFee, "Fee too low");
        emit TaxFeeChanged(taxFee, _newFee);
        taxFee = _newFee;
    }

    function grantMaxRecipients(address account) external onlyOwner {
        maxRecipientsOverride[account] = true;
        emit MaxRecipientsGranted(account);
    }

    function setRateLimitInterval(uint256 _interval) external onlyOwner {
        emit RateLimitIntervalChanged(rateLimitInterval, _interval);
        rateLimitInterval = _interval;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function addBlacklist(address account) external onlyOwner {
        require(account != owner(), "Cannot blacklist owner");
        blacklist[account] = true;
        emit BlacklistAdded(account);
    }

    function delBlacklist(address account) external onlyOwner {
        blacklist[account] = false;
        emit BlacklistRemoved(account);
    }

    function addWhitelistERC20(address token) external onlyOwner {
        whitelistERC20[token] = true;
        emit WhitelistERC20Added(token);
    }

    function delWhitelistERC20(address token) external onlyOwner {
        whitelistERC20[token] = false;
        emit WhitelistERC20Removed(token);
    }

    function addWhitelistERC721(address token) external onlyOwner {
        whitelistERC721[token] = true;
        emit WhitelistERC721Added(token);
    }

    function delWhitelistERC721(address token) external onlyOwner {
        whitelistERC721[token] = false;
        emit WhitelistERC721Removed(token);
    }

    function addWhitelistERC1155(address token) external onlyOwner {
        whitelistERC1155[token] = true;
        emit WhitelistERC1155Added(token);
    }

    function delWhitelistERC1155(address token) external onlyOwner {
        whitelistERC1155[token] = false;
        emit WhitelistERC1155Removed(token);
    }

    // Rescue ETH when paused
    function rescueETH(address payable to) external onlyOwner whenPaused {
        require(to != address(0), "Zero address");
        uint256 bal = address(this).balance;
        emit Rescue(to, bal);
        emit OnlyPausedWithdrawAllowed();
        to.transfer(bal);
    }

    // Main multi-transfer function
    function multiTransfer(
        // ETH
        address[] calldata ethRecipients,
        uint256[] calldata ethAmounts,
        // ERC-20
        address[] calldata erc20Tokens,
        address[] calldata erc20Recipients,
        uint256[] calldata erc20Amounts,
        // ERC-721
        address[] calldata erc721Tokens,
        address[] calldata erc721Recipients,
        uint256[] calldata erc721Ids,
        // ERC-1155
        address[] calldata erc1155Tokens,
        address[] calldata erc1155Recipients,
        uint256[] calldata erc1155Ids,
        uint256[] calldata erc1155Amounts,
        // Anti-replay
        bytes32 nonce
    ) external payable nonReentrant whenNotPaused notBlacklisted(msg.sender) {
        // Rate limit
        require(
            block.timestamp >= lastUsed[msg.sender] + rateLimitInterval,
            "Rate limit"
        );
        lastUsed[msg.sender] = block.timestamp;

        // Nonce check
        require(!usedNonces[nonce], "Nonce used");
        usedNonces[nonce] = true;
        emit NonceUsed(nonce);

        // Check recipients count
        uint256 totalOps = ethRecipients.length +
            erc20Recipients.length +
            erc721Recipients.length +
            erc1155Recipients.length;
        if (gasleft() > gasLimitGlobal) {
            emit GasLimitTooHigh("global");
            revert("Global gas limit too high");
        }

        uint256 maxR = maxRecipientsOverride[msg.sender]
            ? 20
            : defaultMaxRecipients;
        require(
            ethRecipients.length <= maxR &&
                erc20Recipients.length <= maxR &&
                erc721Recipients.length <= maxR &&
                erc1155Recipients.length <= maxR,
            "Too many recipients"
        );

        // Collect needed ETH
        uint256 totalEth = 0;
        for (uint i = 0; i < ethAmounts.length; i++) {
            require(ethRecipients[i] != address(0), "Zero address");
            require(!blacklist[ethRecipients[i]], "Recipient blacklisted");
            require(gasleft() >= gasLimitEth, "ETH gas limit");
            totalEth += ethAmounts[i];
        }
        require(msg.value == totalEth + taxFee, "Incorrect ETH sent");

        // Distribute ETH
        for (uint i = 0; i < ethRecipients.length; i++) {
            payable(ethRecipients[i]).transfer(ethAmounts[i]);
        }

        // ERC-20 transfers
        require(
            erc20Tokens.length == erc20Recipients.length &&
                erc20Recipients.length == erc20Amounts.length,
            "ERC20 array mismatch"
        );
        for (uint i = 0; i < erc20Recipients.length; i++) {
            require(gasleft() >= gasLimitErc20, "ERC20 gas limit");
            require(erc20Recipients[i] != address(0), "Zero address");
            require(!blacklist[erc20Recipients[i]], "Recipient blacklisted");
            require(whitelistERC20[erc20Tokens[i]], "ERC20 not whitelisted");
            IERC20(erc20Tokens[i]).safeTransferFrom(
                msg.sender,
                erc20Recipients[i],
                erc20Amounts[i]
            );
        }

        // ERC-721 transfers
        require(
            erc721Tokens.length == erc721Recipients.length &&
                erc721Recipients.length == erc721Ids.length,
            "ERC721 array mismatch"
        );
        for (uint i = 0; i < erc721Recipients.length; i++) {
            require(gasleft() >= gasLimitErc721, "ERC721 gas limit");
            require(erc721Recipients[i] != address(0), "Zero address");
            require(!blacklist[erc721Recipients[i]], "Recipient blacklisted");
            require(whitelistERC721[erc721Tokens[i]], "ERC721 not whitelisted");
            IERC721(erc721Tokens[i]).safeTransferFrom(
                msg.sender,
                erc721Recipients[i],
                erc721Ids[i]
            );
        }

        // ERC-1155 transfers
        require(
            erc1155Tokens.length == erc1155Recipients.length &&
                erc1155Recipients.length == erc1155Ids.length &&
                erc1155Ids.length == erc1155Amounts.length,
            "ERC1155 array mismatch"
        );
        for (uint i = 0; i < erc1155Recipients.length; i++) {
            require(gasleft() >= gasLimitErc1155, "ERC1155 gas limit");
            require(erc1155Recipients[i] != address(0), "Zero address");
            require(!blacklist[erc1155Recipients[i]], "Recipient blacklisted");
            require(
                whitelistERC1155[erc1155Tokens[i]],
                "ERC1155 not whitelisted"
            );
            IERC1155(erc1155Tokens[i]).safeTransferFrom(
                msg.sender,
                erc1155Recipients[i],
                erc1155Ids[i],
                erc1155Amounts[i],
                ""
            );
        }

        emit MultiTransfer(
            msg.sender,
            ethRecipients.length,
            erc20Recipients.length,
            erc721Recipients.length,
            erc1155Recipients.length,
            nonce
        );
    }

    // Fallback reject other tokens
    receive() external payable {
        require(msg.sender != address(this), "Reject contract token");
    }

    fallback() external payable {
        require(msg.sender != address(this), "Reject contract token");
    }
}