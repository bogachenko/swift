pragma solidity ^0.8.20;

// TransferSWIFT <https://github.com/bogachenko/swift>
// License: MIT
// Version 0.0.0.3 (unstable)

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract TransferSWIFT is Initializable, OwnableUpgradeable {
    uint256 public constant maxRecipients = 15;
    uint256 public constant taxFee = 0.003 ether;

    string public name;
    string public symbol;

    bool public paused;
    address public royaltyCollector;

    mapping(address => bool) public blacklist;
    mapping(address => bool) public whitelist;

    // Новое: Ограничение по времени
    mapping(address => uint256) public lastCall;

    event Paused();
    event Unpaused();
    event RoyaltyPaid(address indexed payer, uint256 amount);
    event BlacklistUpdated(address indexed acct, bool blocked);
    event WhitelistUpdated(address indexed token, bool allowed);
    event BatchTransfer(
        address indexed sender,
        address indexed to,
        string tokenType,
        address token,
        uint256 amountOrId
    );

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    function initialize() public initializer {
        __Ownable_init();
        name = "TransferSWIFT";
        symbol = "SWIFT";
        royaltyCollector = address(this);
        paused = false;
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused();
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused();
    }

    function updateBlacklist(address acct, bool blocked) external onlyOwner {
        blacklist[acct] = blocked;
        emit BlacklistUpdated(acct, blocked);
    }

    function updateWhitelist(address token, bool allowed) external onlyOwner {
        whitelist[token] = allowed;
        emit WhitelistUpdated(token, allowed);
    }

    function batchTransfer(
        address[] calldata recipients,
        string[] calldata tokenTypes,
        address[] calldata tokenAddrs,
        uint256[] calldata amtsOrIds,
        uint256[] calldata erc1155Ids
    ) external payable whenNotPaused {
        require(
            block.timestamp - lastCall[msg.sender] >= 30 minutes,
            "Wait 30 mins between transfers"
        );
        lastCall[msg.sender] = block.timestamp;

        require(recipients.length <= maxRecipients, "Too many recipients");
        require(
            recipients.length == tokenTypes.length &&
                tokenTypes.length == tokenAddrs.length &&
                tokenAddrs.length == amtsOrIds.length,
            "Array length mismatch"
        );
        require(msg.value >= taxFee, "Need royalty fee");

        emit RoyaltyPaid(msg.sender, taxFee);

        for (uint i; i < recipients.length; i++) {
            address to = recipients[i];
            require(!blacklist[to], "Recipient blacklisted");

            string memory t = tokenTypes[i];
            address tk = tokenAddrs[i];
            uint256 v = amtsOrIds[i];

            require(whitelist[tk], "Token not whitelisted");

            if (keccak256(bytes(t)) == keccak256("ERC20")) {
                IERC20(tk).transferFrom(msg.sender, to, v);
            } else if (keccak256(bytes(t)) == keccak256("ERC721")) {
                IERC721(tk).safeTransferFrom(msg.sender, to, v);
            } else if (keccak256(bytes(t)) == keccak256("ERC1155")) {
                IERC1155(tk).safeTransferFrom(
                    msg.sender,
                    to,
                    erc1155Ids[i],
                    v,
                    ""
                );
            } else if (keccak256(bytes(t)) == keccak256("ETH")) {
                payable(to).transfer(v);
            } else {
                revert("Unsupported type");
            }

            emit BatchTransfer(msg.sender, to, t, tk, v);
        }
    }

    function withdrawRoyalties(address payable to) external onlyOwner {
        to.transfer(address(this).balance);
    }

    receive() external payable {}
}