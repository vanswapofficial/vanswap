// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./SimpleToken.sol";

contract SimpleTokenFactory is Ownable, ReentrancyGuard {
    uint256 public createFee = 10 ether;
    address[] public allTokens;
    mapping(address => address[]) public userTokens;

    event TokenCreated(
        address indexed user,
        address tokenAddress,
        string name,
        string symbol,
        uint8 decimals,
        uint256 initialSupply
    );
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event FeesWithdrawn(address indexed owner, uint256 amount);
    event EmergencyWithdraw(address indexed token, uint256 amount);

    constructor() Ownable(msg.sender) {}

    function createToken(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply
    ) external payable nonReentrant returns (address) {
        require(msg.value == createFee, "Incorrect VANA fee");
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(symbol).length > 0, "Symbol cannot be empty");
        require(initialSupply > 0, "Initial supply must be greater than 0");
        require(decimals <= 18, "Decimals cannot exceed 18");

        // Deploy token (factory = msg.sender di dalam token)
        SimpleToken newToken = new SimpleToken(
            name,
            symbol,
            decimals,
            initialSupply
        );

        // Lalu mint ke user pemanggil
        newToken.initialize(msg.sender, initialSupply);

        address tokenAddress = address(newToken);
        allTokens.push(tokenAddress);
        userTokens[msg.sender].push(tokenAddress);

        emit TokenCreated(
            msg.sender,
            tokenAddress,
            name,
            symbol,
            decimals,
            initialSupply
        );

        return tokenAddress;
    }

    // --- Fee Management ---
    function updateFee(uint256 newFee) external onlyOwner {
        require(newFee > 0, "Fee must be greater than 0");
        uint256 oldFee = createFee;
        createFee = newFee;
        emit FeeUpdated(oldFee, newFee);
    }

    receive() external payable {}

    function getTotalTokens() external view returns (uint256) {
        return allTokens.length;
    }

    function getUserTokens(address user) external view returns (address[] memory) {
        return userTokens[user];
    }

    function withdrawFees() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No VANA fees to withdraw");

        payable(owner()).transfer(balance);
        emit FeesWithdrawn(owner(), balance);
    }

    // --- ERC20 Management (for mis-sent tokens) ---
    function withdrawERC20(address tokenAddress) external onlyOwner nonReentrant {
        require(tokenAddress != address(0), "Invalid token address");
        uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");
        IERC20(tokenAddress).transfer(owner(), balance);
        emit EmergencyWithdraw(tokenAddress, balance);
    }
}
