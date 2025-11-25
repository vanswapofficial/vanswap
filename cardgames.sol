// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VansGameTreasury is ReentrancyGuard, Ownable {
    // ============ HARDCODED TOKEN ADDRESSES (VANA CHAIN) ============
    
    // USDC Token on VANA Chain
    IERC20 public constant USDC_TOKEN = IERC20(0xF1815bd50389c46847f0Bda824eC8da914045D14);
    
    // VANS Token on VANA Chain  
    IERC20 public constant VANS_TOKEN = IERC20(0x82741ff5937933244eb562A4b396f8079F1de914);

    // VANA adalah NATIVE token di VANA Chain

    // ============ CONSTANTS ============
    uint256 public constant MIN_CLAIM_VANS = 100 * 10**18;     // 100 VANS
    
    // Chance Packages & Prices (dalam VANA NATIVE token)
    uint256[] public chancePackages = [3, 10, 25, 50];
    uint256[] public nativePrices = [
        3 * 10**16,    // 0.03 VANA for 3 chances
        8 * 10**16,    // 0.08 VANA for 10 chances  
        18 * 10**16,   // 0.18 VANA for 25 chances
        35 * 10**16    // 0.35 VANA for 50 chances
    ];

    // USDC Prices (6 decimals)
    uint256[] public usdcPrices = [
        3 * 10**4,     // 0.03 USDC for 3 chances
        8 * 10**4,     // 0.08 USDC for 10 chances
        18 * 10**4,    // 0.18 USDC for 25 chances
        35 * 10**4     // 0.35 USDC for 50 chances
    ];

    // ============ STATE VARIABLES ============
    mapping(address => uint256) public vansBalances;
    
    uint256 public totalVansClaimed;
    uint256 public totalChancesSold;
    uint256 public totalRevenueNative; // VANA native token revenue
    uint256 public totalRevenueUSDC;

    // ============ EVENTS ============
    event VansClaimed(address indexed user, uint256 amount);
    event ChancesPurchased(address indexed user, address token, uint256 packageIndex, uint256 chances, uint256 price);
    event RevenueWithdrawn(address indexed owner, address token, uint256 amount);
    event PricesUpdated();

    // ============ MODIFIERS ============
    modifier validPackage(uint256 packageIndex) {
        require(packageIndex < chancePackages.length, "Invalid package");
        _;
    }

    // ============ CONSTRUCTOR ============
    constructor() Ownable(msg.sender) {
        // No need to initialize tokens - they are hardcoded
    }

    // ============ USER FUNCTIONS ============

    /**
     * @dev Claim VANS tokens earned from off-chain games
     */
    function claimVans(uint256 amount) external nonReentrant {
        require(amount >= MIN_CLAIM_VANS, "Below minimum claim");
        require(VANS_TOKEN.balanceOf(address(this)) >= amount, "Insufficient VANS in contract");
        
        vansBalances[msg.sender] += amount;
        totalVansClaimed += amount;
        
        require(VANS_TOKEN.transfer(msg.sender, amount), "VANS transfer failed");
        emit VansClaimed(msg.sender, amount);
    }

    /**
     * @dev Purchase chances with VANA NATIVE token
     */
    function purchaseChancesWithNative(uint256 packageIndex) 
        external 
        payable 
        nonReentrant 
        validPackage(packageIndex) 
    {
        uint256 price = nativePrices[packageIndex];
        uint256 chances = chancePackages[packageIndex];
        
        require(msg.value >= price, "Insufficient VANA sent");
        
        // Refund excess native tokens
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
        
        totalRevenueNative += price;
        totalChancesSold += chances;
        
        emit ChancesPurchased(msg.sender, address(0), packageIndex, chances, price);
    }

    /**
     * @dev Purchase chances with USDC tokens
     */
    function purchaseChancesWithUSDC(uint256 packageIndex) 
        external 
        nonReentrant 
        validPackage(packageIndex) 
    {
        uint256 price = usdcPrices[packageIndex];
        uint256 chances = chancePackages[packageIndex];
        
        require(USDC_TOKEN.transferFrom(msg.sender, address(this), price), "USDC transfer failed");
        
        totalRevenueUSDC += price;
        totalChancesSold += chances;
        
        emit ChancesPurchased(msg.sender, address(USDC_TOKEN), packageIndex, chances, price);
    }

    // ============ OWNER FUNCTIONS ============

    /**
     * @dev Withdraw all VANA native tokens
     */
    function withdrawAllNative() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No VANA to withdraw");
        
        payable(owner()).transfer(balance);
        totalRevenueNative = 0;
        
        emit RevenueWithdrawn(owner(), address(0), balance);
    }

    /**
     * @dev Withdraw all USDC revenue
     */
    function withdrawAllUSDC() external onlyOwner nonReentrant {
        uint256 balance = USDC_TOKEN.balanceOf(address(this));
        require(balance > 0, "No USDC to withdraw");
        
        require(USDC_TOKEN.transfer(owner(), balance), "USDC transfer failed");
        totalRevenueUSDC = 0;
        
        emit RevenueWithdrawn(owner(), address(USDC_TOKEN), balance);
    }

    /**
     * @dev Withdraw excess VANS tokens
     */
    function withdrawExcessVANS(uint256 amount) external onlyOwner nonReentrant {
        require(VANS_TOKEN.transfer(owner(), amount), "VANS transfer failed");
        emit RevenueWithdrawn(owner(), address(VANS_TOKEN), amount);
    }

    /**
     * @dev Update prices
     */
    function updatePrices(
        uint256[] calldata newNativePrices, 
        uint256[] calldata newUsdcPrices
    ) external onlyOwner {
        require(newNativePrices.length == chancePackages.length, "Invalid native prices length");
        require(newUsdcPrices.length == chancePackages.length, "Invalid USDC prices length");
        
        nativePrices = newNativePrices;
        usdcPrices = newUsdcPrices;
        
        emit PricesUpdated();
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Get package information
     */
    function getPackageInfo(uint256 packageIndex) 
        external 
        view 
        validPackage(packageIndex) 
        returns (
            uint256 chances,
            uint256 nativePrice, 
            uint256 usdcPrice
        ) 
    {
        return (chancePackages[packageIndex], nativePrices[packageIndex], usdcPrices[packageIndex]);
    }

    /**
     * @dev Get contract balances
     */
    function getContractBalances() external view returns (
        uint256 nativeBalance,  // VANA balance
        uint256 usdcBalance,
        uint256 vansBalance
    ) {
        return (
            address(this).balance,
            USDC_TOKEN.balanceOf(address(this)),
            VANS_TOKEN.balanceOf(address(this))
        );
    }

    /**
     * @dev Get contract statistics
     */
    function getStats() external view returns (
        uint256 totalClaims,
        uint256 totalChances,
        uint256 nativeRevenue,  // VANA revenue
        uint256 usdcRevenue
    ) {
        return (totalVansClaimed, totalChancesSold, totalRevenueNative, totalRevenueUSDC);
    }

    /**
     * @dev Check if user can claim
     */
    function canClaim(uint256 amount) external view returns (bool) {
        return amount >= MIN_CLAIM_VANS && VANS_TOKEN.balanceOf(address(this)) >= amount;
    }

    // ============ RECEIVE FUNCTION ============
    
    /**
     * @dev Allow contract to receive VANA native tokens
     */
    receive() external payable {}
}