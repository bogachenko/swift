// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import "@openzeppelin/contracts/interfaces/IERC1155Receiver.sol";
contract TestCOIN is ERC20, ERC20Permit, ERC20Pausable, Ownable, IERC721Receiver, IERC1155Receiver {
    constructor()
        ERC20("TestCOIN", "tCOIN")
        ERC20Permit("TestCOIN")
        Ownable(msg.sender)
    {
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
    }
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
    function burnFrom(address account, uint256 amount) external {
        uint256 currentAllowance = allowance(account, msg.sender);
        require(currentAllowance >= amount, "Burn amount exceeds allowance");
        _approve(account, msg.sender, currentAllowance - amount);
        _burn(account, amount);
    }
    function pause() external onlyOwner {
        _pause();
    }
    function unpause() external onlyOwner {
        _unpause();
    }
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
    }
    receive() external payable {
        revert("Contract does not accept ETH");
    }
    fallback() external payable {
        revert("Contract does not accept fallback calls");
    }
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        revert("NFTs not accepted");
    }
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure override returns (bytes4) {
        revert("ERC1155 not accepted");
    }
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure override returns (bytes4) {
        revert("ERC1155 batch not accepted");
    }
    function supportsInterface(bytes4) public pure override returns (bool) {
        return false;
    }
    function tokenFallback(address, uint256, bytes calldata) external pure {
        revert("ERC20 not accepted");
    }
}