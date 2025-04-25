// TransferSWIFT <https://github.com/bogachenko/swift>
// License: MIT
// Version 0.0.0.1 (unstable)

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract TransferSWIFT is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    string public constant name = "TransferSWIFT";
    string public constant symbol = "SWIFT";

    uint256 public constant MIN_TAX_FEE = 1e14; // 0.0001 ETH
    uint256 public taxFee = MIN_TAX_FEE;

    uint256 public defaultMaxRecipients = 15;
    mapping(address => uint256) public maxRecipientsOverride;

    mapping(address => uint256) public lastUsed;
    uint256 public rateLimitInterval = 10 minutes;

    mapping(address => bool) public blacklist;
    mapping(address => bool) public whitelistERC20;
    mapping(address => bool) public whitelistERC721;
    mapping(address => bool) public whitelistERC1155;

    mapping(bytes32 => bool) private usedNonces;

    event MultiTransfer(
        address indexed sender,
        uint256 ethCount,
        uint256 erc20Count,
        uint256 erc721Count,
        uint256 erc1155Count,
        bytes32 nonce
    );
    event TaxFeeChanged(uint256 oldFee, uint256 newFee);
    event MaxRecipientsChanged(address indexed account, uint256 oldMax, uint256 newMax);
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

    modifier notBlacklisted(address account) {
        require(!blacklist[account], "Address blacklisted");
        _;
    }

    constructor() payable Ownable(msg.sender) {}

    // Owner functions
    function setTaxFee(uint256 _newFee) external onlyOwner {
        require(_newFee >= MIN_TAX_FEE, "Fee too low");
        emit TaxFeeChanged(taxFee, _newFee);
        taxFee = _newFee;
    }

    function setMaxRecipients(address account, uint256 maxCount) external onlyOwner {
        require(maxCount <= 20, "Max 20 recipients");
        emit MaxRecipientsChanged(account, maxRecipientsOverride[account], maxCount);
        maxRecipientsOverride[account] = maxCount;
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
        blacklist[account] = true;
        emit BlacklistAdded(account);
    }

    function removeBlacklist(address account) external onlyOwner {
        blacklist[account] = false;
        emit BlacklistRemoved(account);
    }

    function addWhitelistERC20(address token) external onlyOwner {
        whitelistERC20[token] = true;
        emit WhitelistERC20Added(token);
    }

    function removeWhitelistERC20(address token) external onlyOwner {
        whitelistERC20[token] = false;
        emit WhitelistERC20Removed(token);
    }

    function addWhitelistERC721(address token) external onlyOwner {
        whitelistERC721[token] = true;
        emit WhitelistERC721Added(token);
    }

    function removeWhitelistERC721(address token) external onlyOwner {
        whitelistERC721[token] = false;
        emit WhitelistERC721Removed(token);
    }

    function addWhitelistERC1155(address token) external onlyOwner {
        whitelistERC1155[token] = true;
        emit WhitelistERC1155Added(token);
    }

    function removeWhitelistERC1155(address token) external onlyOwner {
        whitelistERC1155[token] = false;
        emit WhitelistERC1155Removed(token);
    }

    // Rescue ETH when paused
    function rescueETH(address payable to) external onlyOwner whenPaused {
        uint256 bal = address(this).balance;
        emit Rescue(to, bal);
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
        require(block.timestamp >= lastUsed[msg.sender] + rateLimitInterval, "Rate limit");
        lastUsed[msg.sender] = block.timestamp;

        // Nonce check
        require(!usedNonces[nonce], "Nonce used");
        usedNonces[nonce] = true;
        emit NonceUsed(nonce);

        // Check recipients count
        uint256 maxR = maxRecipientsOverride[msg.sender] > 0 ? maxRecipientsOverride[msg.sender] : defaultMaxRecipients;
        require(
            ethRecipients.length <= maxR,
            "Too many ETH recipients"
        );
        require(
            erc20Recipients.length <= maxR,
            "Too many ERC20 recipients"
        );
        require(
            erc721Recipients.length <= maxR,
            "Too many ERC721 recipients"
        );
        require(
            erc1155Recipients.length <= maxR,
            "Too many ERC1155 recipients"
        );

        // Collect needed ETH
        uint256 totalEth = 0;
        for (uint i = 0; i < ethAmounts.length; i++) {
            totalEth += ethAmounts[i];
        }
        require(msg.value == totalEth + taxFee, "Incorrect ETH sent");

        // Distribute ETH
        for (uint i = 0; i < ethRecipients.length; i++) {
            address to = ethRecipients[i];
            require(!blacklist[to], "Recipient blacklisted");
            payable(to).transfer(ethAmounts[i]);
        }

        // ERC-20 transfers
        require(
            erc20Tokens.length == erc20Recipients.length &&
            erc20Recipients.length == erc20Amounts.length,
            "ERC20 array mismatch"
        );
        for (uint i = 0; i < erc20Recipients.length; i++) {
            address token = erc20Tokens[i];
            require(whitelistERC20[token], "ERC20 not whitelisted");
            address to = erc20Recipients[i];
            require(!blacklist[to], "Recipient blacklisted");
            IERC20(token).safeTransferFrom(msg.sender, to, erc20Amounts[i]);
        }

        // ERC-721 transfers
        require(
            erc721Tokens.length == erc721Recipients.length &&
            erc721Recipients.length == erc721Ids.length,
            "ERC721 array mismatch"
        );
        for (uint i = 0; i < erc721Recipients.length; i++) {
            address token = erc721Tokens[i];
            require(whitelistERC721[token], "ERC721 not whitelisted");
            address to = erc721Recipients[i];
            require(!blacklist[to], "Recipient blacklisted");
            IERC721(token).safeTransferFrom(msg.sender, to, erc721Ids[i]);
        }

        // ERC-1155 transfers
        require(
            erc1155Tokens.length == erc1155Recipients.length &&
            erc1155Recipients.length == erc1155Ids.length &&
            erc1155Ids.length == erc1155Amounts.length,
            "ERC1155 array mismatch"
        );
        for (uint i = 0; i < erc1155Recipients.length; i++) {
            address token = erc1155Tokens[i];
            require(whitelistERC1155[token], "ERC1155 not whitelisted");
            address to = erc1155Recipients[i];
            require(!blacklist[to], "Recipient blacklisted");
            IERC1155(token).safeTransferFrom(msg.sender, to, erc1155Ids[i], erc1155Amounts[i], "");
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
    receive() external payable {}
    fallback() external payable {}
}