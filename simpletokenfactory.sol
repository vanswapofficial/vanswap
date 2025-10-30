// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ISimpleToken {
    // hanya untuk kompatibilitas jika perlu; tidak dipakai wajib
}

/**
 * @title SimpleTokenFactory
 * @dev Factory untuk deploy SimpleToken. Factory menerima fee (native).
 * Factory bisa menahan native/ERC20 (misal: accidental transfer) dan owner factory
 * dapat menariknya. Namun factory **tidak** menjadi owner token buatan user.
 */
contract SimpleTokenFactory is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public createFee = 10 ether; // default 10 VANA
    address[] public allTokens;
    mapping(address => address[]) public userTokens;

    event TokenCreated(
        address indexed user,
        address indexed tokenAddress,
        string name,
        string symbol,
        uint8 decimals,
        uint256 initialSupply
    );
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event FeesWithdrawn(address indexed owner, uint256 amount);
    event NativeReceived(address indexed sender, uint256 amount);
    event ERC20Withdrawn(address indexed token, address indexed to, uint256 amount);

    constructor() {}

    /**
     * @notice User membayar fee dan membuat token; user menjadi owner token.
     */
    function createToken(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply
    ) external payable nonReentrant returns (address) {
        require(msg.value == createFee, "Incorrect VANA fee");
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(symbol).length > 0, "Symbol cannot be empty");
        require(initialSupply > 0, "Initial supply must be > 0");
        require(decimals <= 18, "Decimals cannot exceed 18");

        SimpleToken newToken = new SimpleToken(
            name,
            symbol,
            decimals,
            initialSupply,
            msg.sender
        );

        address tokenAddress = address(newToken);
        allTokens.push(tokenAddress);
        userTokens[msg.sender].push(tokenAddress);

        emit TokenCreated(msg.sender, tokenAddress, name, symbol, decimals, initialSupply);
        return tokenAddress;
    }

    /**
     * @notice Update fee (hanya owner factory)
     */
    function updateFee(uint256 newFee) external onlyOwner {
        require(newFee > 0 && newFee <= 100 ether, "Invalid fee");
        uint256 old = createFee;
        createFee = newFee;
        emit FeeUpdated(old, newFee);
    }

    // menerima native ke factory (misal transfer langsung)
    receive() external payable {
        emit NativeReceived(msg.sender, msg.value);
    }

    /**
     * @notice Owner factory menarik seluruh native (fee) yang ada di factory
     */
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        require(bal > 0, "No fees to withdraw");
        (bool ok, ) = payable(owner()).call{value: bal}("");
        require(ok, "Withdraw failed");
        emit FeesWithdrawn(owner(), bal);
    }

    /**
     * @notice Owner factory menarik token ERC20 yang tersimpan di factory (misal accidental transfer)
     */
    function withdrawERC20(address tokenAddress, address to, uint256 amount) external onlyOwner nonReentrant {
        require(tokenAddress != address(0), "Invalid token");
        require(to != address(0), "Invalid recipient");
        uint256 bal = IERC20(tokenAddress).balanceOf(address(this));
        require(amount <= bal, "Insufficient token balance");
        IERC20(tokenAddress).safeTransfer(to, amount);
        emit ERC20Withdrawn(tokenAddress, to, amount);
    }

    /**
     * @notice Helper views
     */
    function getTotalTokens() external view returns (uint256) {
        return allTokens.length;
    }

    function getUserTokens(address user) external view returns (address[] memory) {
        return userTokens[user];
    }

    function getCreateFee() external view returns (uint256) {
        return createFee;
    }
}
