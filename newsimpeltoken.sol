// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SimpleTokenFactory
 * @notice Factory yang membuat token ERC20 untuk user.
 * Factory bisa menerima & mengirim native dan ERC20 (misal sebagai hasil fee).
 */
contract SimpleTokenFactory is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public createFee = 10 ether; // 10 VANA
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
    event NativeReceived(address indexed sender, uint256 amount);
    event NativeTransferred(address indexed to, uint256 amount);
    event ERC20Transferred(address indexed token, address indexed to, uint256 amount);

    constructor() {}

    /**
     * @notice Membuat token baru dengan user sebagai owner token
     */
    function createToken(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply
    ) external payable nonReentrant returns (address) {
        require(msg.value == createFee, "Incorrect VANA fee");
        require(bytes(name).length > 0, "Name required");
        require(bytes(symbol).length > 0, "Symbol required");
        require(initialSupply > 0, "Initial supply > 0");
        require(decimals <= 18, "Max decimals 18");

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
     * @notice Update biaya pembuatan token
     */
    function updateFee(uint256 newFee) external onlyOwner {
        require(newFee > 0 && newFee <= 100 ether, "Invalid fee range");
        uint256 old = createFee;
        createFee = newFee;
        emit FeeUpdated(old, newFee);
    }

    /**
     * @notice Menerima native token (misal fee atau accidental transfer)
     */
    receive() external payable {
        emit NativeReceived(msg.sender, msg.value);
    }

    /**
     * @notice Owner factory menarik seluruh native (VANA)
     */
    function withdrawNative(uint256 amount) external onlyOwner nonReentrant {
        require(amount <= address(this).balance, "Insufficient balance");
        payable(owner()).transfer(amount);
        emit NativeTransferred(owner(), amount);
    }

    /**
     * @notice Owner factory menarik ERC20 token yang tersimpan di factory
     */
    function withdrawERC20(address token, uint256 amount) external onlyOwner nonReentrant {
        require(token != address(0), "Invalid token");
        IERC20(token).safeTransfer(owner(), amount);
        emit ERC20Transferred(token, owner(), amount);
    }

    /**
     * @notice Ambil daftar semua token yang pernah dibuat
     */
    function getAllTokens() external view returns (address[] memory) {
        return allTokens;
    }

    /**
     * @notice Ambil token-token milik user tertentu
     */
    function getUserTokens(address user) external view returns (address[] memory) {
        return userTokens[user];
    }
}
