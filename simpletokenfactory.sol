// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SimpleToken - ERC20 Token generator
contract SimpleToken is ERC20 {
    uint8 private _decimals;
    address public owner;
    
    constructor(
        string memory name_,
        string memory symbol_, 
        uint8 decimals_,
        uint256 initialSupply_
    ) ERC20(name_, symbol_) {
        _decimals = decimals_;
        owner = msg.sender; // User yang deploy adalah OWNER
        _mint(msg.sender, initialSupply_); // Mint ke user
    }
    
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    // ✅ msg.sender adalah OWNER token
    // ❌ NO blacklist/whitelist
    // ❌ NO anti-whale
    // ❌ NO fee changes
    // ❌ NO pausable
}

/**
 * @title SimpleTokenFactory - Factory untuk deploy token
 * @dev Fee dalam VANA (native) saja, dev bisa ubah fee
 */
contract SimpleTokenFactory is Ownable, ReentrancyGuard {
    uint256 public createFee = 10 ether; // 10 VANA - BISA DIUBAH
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
    
    /**
     * @dev Create token baru dengan fee VANA
     * @param name Nama token
     * @param Symbol simbol token
     * @param decimals Decimal token
     * @param initialSupply Supply awal
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
        require(initialSupply > 0, "Initial supply must be greater than 0");
        require(decimals <= 18, "Decimals cannot exceed 18");
        
        // Deploy token baru - msg.sender otomatis jadi OWNER
        SimpleToken newToken = new SimpleToken(
            name,
            symbol,
            decimals,
            initialSupply
            // Tidak perlu kirim address, msg.sender otomatis jadi owner
        );
        
        address tokenAddress = address(newToken);
        
        // Simpan data
        allTokens.push(tokenAddress);
        userTokens[msg.sender].push(tokenAddress);
        
        emit TokenCreated(
            msg.sender, // User adalah pemilik
            tokenAddress,
            name,
            symbol,
            decimals,
            initialSupply
        );
        
        return tokenAddress;
    }
    
    /**
     * @dev Update fee (hanya owner)
     */
    function updateFee(uint256 newFee) external onlyOwner {
        require(newFee > 0, "Fee must be greater than 0");
        uint256 oldFee = createFee;
        createFee = newFee;
        emit FeeUpdated(oldFee, newFee);
    }
    
    /**
     * @dev Receive native tokens (VANA)
     */
    receive() external payable {}
    
    /**
     * @dev Get total tokens created
     */
    function getTotalTokens() external view returns (uint256) {
        return allTokens.length;
    }
    
    /**
     * @dev Get user's tokens
     */
    function getUserTokens(address user) external view returns (address[] memory) {
        return userTokens[user];
    }
    
    /**
     * @dev Get current fee
     */
    function getCreateFee() external view returns (uint256) {
        return createFee;
    }
    
    /**
     * @dev Withdraw collected VANA fees to owner
     */
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No VANA fees to withdraw");
        
        payable(owner()).transfer(balance);
        emit FeesWithdrawn(owner(), balance);
    }
    
    /**
     * @dev Withdraw ERC20 tokens (jika ada yang salah kirim)
     */
    function withdrawERC20(address tokenAddress) external onlyOwner nonReentrant {
        require(tokenAddress != address(0), "Invalid token address");
        
        uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");
        
        IERC20(tokenAddress).transfer(owner(), balance);
        emit EmergencyWithdraw(tokenAddress, balance);
    }
    
    /**
     * @dev Transfer native tokens (VANA) - untuk management
     */
    function transferNative(address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient");
        require(amount <= address(this).balance, "Insufficient balance");
        
        payable(to).transfer(amount);
    }
    
    /**
     * @dev Transfer ERC20 tokens - untuk management
     */
    function transferERC20(address tokenAddress, address to, uint256 amount) external onlyOwner nonReentrant {
        require(tokenAddress != address(0), "Invalid token address");
        require(to != address(0), "Invalid recipient");
        
        IERC20(tokenAddress).transfer(to, amount);
    }
    
    // ✅ Interface untuk ERC20
    interface IERC20 {
        function balanceOf(address account) external view returns (uint256);
        function transfer(address to, uint256 amount) external returns (bool);
    }
}