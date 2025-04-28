// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// TransferSWIFT <https://github.com/bogachenko/swift>
// License: MIT
// Version 0.0.0.4 (unstable)

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract TransferSWIFT is ReentrancyGuard, Ownable, Pausable {
    string public name = "TransferSWIFT";
    string public symbol = "SWIFT";

    uint256 public taxFee = 0.0001 ether;
    uint256 public constant MIN_TAX_FEE = 0.0001 ether;
    uint256 public constant MAX_TAX_FEE = 0.0005 ether;

    uint256 public accumulatedRoyalties;

    mapping(address => bool) public blacklisted;
    mapping(address => uint256) public lastUsed;
    mapping(address => bool) public maxRecipients;

    mapping(address => bool) public whitelistERC20;
    mapping(address => bool) public whitelistERC751;
    mapping(address => bool) public whitelistERC1155;

    uint256 public nonce;

    modifier notBlacklisted(address _addr) {
        require(!blacklisted[_addr], "Address blacklisted");
        _;
    }

    modifier rateLimit() {
        require(block.timestamp >= lastUsed[msg.sender] + 60, "Rate limit 60s");
        _;
        lastUsed[msg.sender] = block.timestamp;
    }

    modifier collectRoyalty() {
        require(msg.value >= taxFee, "Insufficient royalty");
        accumulatedRoyalties += msg.value;
        _;
    }

    event MultiTransferETH(address indexed sender, address[] recipients, uint256[] amounts);
    event MultiTransferERC20(address indexed sender, address token, address[] recipients, uint256[] amounts);
    event MultiTransferERC751(address indexed sender, address token, address[] recipients, uint256[] tokenIds);
    event MultiTransferERC1155(address indexed sender, address token, address[] recipients, uint256[] tokenIds, uint256[] amounts);

    // Blacklist functions
    function addBlacklist(address _addr) external onlyOwner {
        blacklisted[_addr] = true;
    }

    function delBlacklist(address _addr) external onlyOwner {
        blacklisted[_addr] = false;
    }

    function checkBlacklist(address _addr) external view returns (bool) {
        return blacklisted[_addr];
    }

    // Whitelist functions
    function addWhitelistERC20(address _addr) external onlyOwner {
        whitelistERC20[_addr] = true;
    }

    function delWhitelistERC20(address _addr) external onlyOwner {
        whitelistERC20[_addr] = false;
    }

    function addWhitelistERC751(address _addr) external onlyOwner {
        whitelistERC751[_addr] = true;
    }

    function delWhitelistERC751(address _addr) external onlyOwner {
        whitelistERC751[_addr] = false;
    }

    function addWhitelistERC1155(address _addr) external onlyOwner {
        whitelistERC1155[_addr] = true;
    }

    function delWhitelistERC1155(address _addr) external onlyOwner {
        whitelistERC1155[_addr] = false;
    }

    // Max recipients
    function setMaxRecipients(address _addr) external onlyOwner {
        maxRecipients[_addr] = true;
    }

    function multiTransferETH(address[] calldata recipients, uint256[] calldata amounts)
        external
        payable
        whenNotPaused
        nonReentrant
        notBlacklisted(msg.sender)
        rateLimit
        collectRoyalty
    {
        require(recipients.length == amounts.length, "Length mismatch");
        uint256 max = maxRecipients[msg.sender] ? 20 : 15;
        require(recipients.length <= max, "Too many recipients");

        uint256 totalAmount;
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Zero address");
            require(!blacklisted[recipients[i]], "Recipient blacklisted");
            totalAmount += amounts[i];
        }
        require(msg.value >= totalAmount + taxFee, "Insufficient ETH");

        for (uint256 i = 0; i < recipients.length; i++) {
            payable(recipients[i]).transfer(amounts[i]);
        }
        emit MultiTransferETH(msg.sender, recipients, amounts);
        nonce++;
    }

    function multiTransferERC20(address token, address[] calldata recipients, uint256[] calldata amounts)
        external
        payable
        whenNotPaused
        nonReentrant
        notBlacklisted(msg.sender)
        rateLimit
        collectRoyalty
    {
        require(whitelistERC20[token], "Token not whitelisted");
        require(recipients.length == amounts.length, "Length mismatch");
        uint256 max = maxRecipients[msg.sender] ? 20 : 15;
        require(recipients.length <= max, "Too many recipients");

        IERC20 erc20 = IERC20(token);

        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Zero address");
            require(!blacklisted[recipients[i]], "Recipient blacklisted");
            require(erc20.transferFrom(msg.sender, recipients[i], amounts[i]), "ERC20 transfer failed");
        }
        emit MultiTransferERC20(msg.sender, token, recipients, amounts);
        nonce++;
    }

    function multiTransferERC751(address token, address[] calldata recipients, uint256[] calldata tokenIds)
        external
        payable
        whenNotPaused
        nonReentrant
        notBlacklisted(msg.sender)
        rateLimit
        collectRoyalty
    {
        require(whitelistERC751[token], "Token not whitelisted");
        require(recipients.length == tokenIds.length, "Length mismatch");
        uint256 max = maxRecipients[msg.sender] ? 20 : 15;
        require(recipients.length <= max, "Too many recipients");

        IERC721 erc721 = IERC721(token);

        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Zero address");
            require(!blacklisted[recipients[i]], "Recipient blacklisted");
            require(erc721.ownerOf(tokenIds[i]) == msg.sender, "Not owner of token");
            erc721.safeTransferFrom(msg.sender, recipients[i], tokenIds[i]);
        }
        emit MultiTransferERC751(msg.sender, token, recipients, tokenIds);
        nonce++;
    }

    function multiTransferERC1155(address token, address[] calldata recipients, uint256[] calldata tokenIds, uint256[] calldata amounts)
        external
        payable
        whenNotPaused
        nonReentrant
        notBlacklisted(msg.sender)
        rateLimit
        collectRoyalty
    {
        require(whitelistERC1155[token], "Token not whitelisted");
        require(recipients.length == tokenIds.length && tokenIds.length == amounts.length, "Length mismatch");
        uint256 max = maxRecipients[msg.sender] ? 20 : 15;
        require(recipients.length <= max, "Too many recipients");

        IERC1155 erc1155 = IERC1155(token);

        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Zero address");
            require(!blacklisted[recipients[i]], "Recipient blacklisted");
            require(erc1155.balanceOf(msg.sender, tokenIds[i]) >= amounts[i], "Not enough balance");
            erc1155.safeTransferFrom(msg.sender, recipients[i], tokenIds[i], amounts[i], "");
        }
        emit MultiTransferERC1155(msg.sender, token, recipients, tokenIds, amounts);
        nonce++;
    }

    function changeTaxFee(uint256 _newFee) external onlyOwner {
        require(_newFee >= MIN_TAX_FEE && _newFee <= MAX_TAX_FEE, "Fee out of range");
        taxFee = _newFee;
    }

    function withdrawRoyalties(address payable to) external onlyOwner {
        to.transfer(accumulatedRoyalties);
        accumulatedRoyalties = 0;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // To receive royalties
    receive() external payable {}
    fallback() external payable {}

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}