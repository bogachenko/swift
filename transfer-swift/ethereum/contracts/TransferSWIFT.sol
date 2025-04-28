// TransferSWIFT <https://github.com/bogachenko/swift>
// License: MIT
// Version 0.0.0.4 (unstable)

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// OpenZeppelin imports
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract TransferSWIFT is ReentrancyGuard, Pausable, ERC165 {
    using Address for address payable;

    address public owner;
    string public name = "TransferSWIFT";
    string public symbol = "SWIFT";

    uint256 public minTaxFee = 0.0001 ether;
    uint256 public maxTaxFee = 0.0005 ether;
    uint256 public taxFee = 0.0001 ether;
    uint256 public accumulatedRoyalties;

    uint256 constant defaultRecipients = 15;
    uint256 constant maxRecipients = 20;

    mapping(address => uint256) public lastUsed;
    mapping(address => bool) public blacklist;
    mapping(address => bool) public extendedRecipients;
    mapping(address => bool) public whitelistERC20;
    mapping(address => bool) public whitelistERC721;
    mapping(address => bool) public whitelistERC1155;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
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

    constructor() {
        owner = msg.sender;
    }

    receive() external payable {}

    // ================= Transfer Functions =================

    function multiTransferETH(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external payable nonReentrant enforceRateLimit whenNotPaused {
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

            totalAmount += amounts[i];
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

    function multiTransferERC20(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external payable nonReentrant enforceRateLimit whenNotPaused {
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

    function multiTransferERC721(
        address token,
        address[] calldata recipients,
        uint256[] calldata tokenIds
    ) external payable nonReentrant enforceRateLimit whenNotPaused {
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

    function multiTransferERC1155(
        address token,
        address[] calldata recipients,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external payable nonReentrant enforceRateLimit whenNotPaused {
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

    // ================= Admin Functions =================

    function setMaxRecipients(address user) external onlyOwner {
        extendedRecipients[user] = true;
    }

    function addBlacklist(address user) external onlyOwner {
        blacklist[user] = true;
    }

    function delBlacklist(address user) external onlyOwner {
        blacklist[user] = false;
    }

    function addWhitelistERC20(address token) external onlyOwner {
        whitelistERC20[token] = true;
    }

    function delWhitelistERC20(address token) external onlyOwner {
        whitelistERC20[token] = false;
    }

    function addWhitelistERC721(address token) external onlyOwner {
        whitelistERC721[token] = true;
    }

    function delWhitelistERC721(address token) external onlyOwner {
        whitelistERC721[token] = false;
    }

    function addWhitelistERC1155(address token) external onlyOwner {
        whitelistERC1155[token] = true;
    }

    function delWhitelistERC1155(address token) external onlyOwner {
        whitelistERC1155[token] = false;
    }

    function setTaxFee(uint256 newFee) external onlyOwner {
        require(
            newFee >= minTaxFee && newFee <= maxTaxFee,
            "Fee out of bounds"
        );
        taxFee = newFee;
    }

    function withdrawRoyalties() external onlyOwner nonReentrant {
        uint256 amount = accumulatedRoyalties;
        require(amount > 0, "No royalties");
        accumulatedRoyalties = 0;
        payable(owner).sendValue(amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ================= ERC165 Support =================

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