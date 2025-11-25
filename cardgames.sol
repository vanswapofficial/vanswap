// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VansGameTreasury is ReentrancyGuard, Ownable {
    // ============ STATE VARIABLES ============
    
    // Token Contracts
    IERC20 public vanaToken;
    IERC20 public usdcToken;
    IERC20 public vansToken;
    
    // Constants
    uint256 public constant MIN_CLAIM_VANS = 100 * 10**18;     // 100 VANS
    
    // Chance Packages & Prices
    uint256[] public chancePackages = [3, 10, 25, 50];
    uint256[] public vanaPrices = [
        1 * 10**16,    // 0.01 VANA for 3 chances
        3 * 10**16,    // 0.03 VANA for 10 chances  
        7 * 10**16,    // 0.07 VANA for 25 chances
        13 * 10**16    // 0.13 VANA for 50 chances
    ];
    uint256[] public usdcPrices = [
        3 * 10**4,     // 0.03 USDC for 3 chances
        8 * 10**4,     // 0.08 USDC for 10 chances
        18 * 10**4,    // 0.18 USDC for 25 chances
        35 * 10**4     // 0.35 USDC for 50 chances
    ];

    // User Balances (HANYA untuk VANS yang diklaim dari game)
    mapping(address => uint256) public vansBalances;
    
    // Tracking
    uint256 public totalVansClaimed;
    uint256 public totalChancesSold;
    uint256 public totalRevenueVANA;
    uint256 public totalRevenueUSDC;

    // ============ EVENTS ============
    
    event VansClaimed(address indexed user, uint256 amount);
    event ChancesPurchased(address indexed user, address token, uint256 packageIndex, uint256 chances, uint256 price);
    event RevenueWithdrawn(address indexed owner, address token, uint256 amount);
    event PricesUpdated(address indexed updater);

    // ============ MODIFIERS ============
    
    modifier validPackage(uint256 packageIndex) {
        require(packageIndex < chancePackages.length, "Invalid package");
        _;
    }

    // ============ CONSTRUCTOR ============
    
    constructor(
        address _vanaToken,
        address _usdcToken, 
        address _vansToken
    ) {
        require(_vanaToken != address(0), "Invalid VANA token");
        require(_usdcToken != address(0), "Invalid USDC token");
        require(_vansToken != address(0), "Invalid VANS token");
        
        vanaToken = IERC20(_vanaToken);
        usdcToken = IERC20(_usdcToken);
        vansToken = IERC20(_vansToken);
    }

    // ============ USER FUNCTIONS ============

    /**
     * @dev Claim VANS tokens earned from off-chain games
     */
    function claimVans(uint256 amount) external nonReentrant {
        require(amount >= MIN_CLAIM_VANS, "Below minimum claim");
        require(vansToken.balanceOf(address(this)) >= amount, "Insufficient VANS in contract");
        
        // Update user balance
        vansBalances[msg.sender] += amount;
        totalVansClaimed += amount;
        
        // Transfer VANS to user
        require(vansToken.transfer(msg.sender, amount), "VANS transfer failed");
        
        emit VansClaimed(msg.sender, amount);
    }

    /**
     * @dev Purchase chances with VANA tokens
     */
    function purchaseChancesWithVANA(uint256 packageIndex) 
        external 
        nonReentrant 
        validPackage(packageIndex) 
    {
        uint256 price = vanaPrices[packageIndex];
        uint256 chances = chancePackages[packageIndex];
        
        // Transfer VANA from user to contract
        require(vanaToken.transferFrom(msg.sender, address(this), price), "VANA transfer failed");
        
        // Update tracking
        totalRevenueVANA += price;
        totalChancesSold += chances;
        
        emit ChancesPurchased(msg.sender, address(vanaToken), packageIndex, chances, price);
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
        
        // Transfer USDC from user to contract
        require(usdcToken.transferFrom(msg.sender, address(this), price), "USDC transfer failed");
        
        // Update tracking
        totalRevenueUSDC += price;
        totalChancesSold += chances;
        
        emit ChancesPurchased(msg.sender, address(usdcToken), packageIndex, chances, price);
    }

    // ============ OWNER FUNCTIONS ============

    /**
     * @dev Withdraw revenue in VANA tokens
     */
    function withdrawVANARevenue(uint256 amount) external onlyOwner nonReentrant {
        require(amount <= totalRevenueVANA, "Exceeds VANA revenue");
        require(vanaToken.transfer(owner(), amount), "VANA transfer failed");
        
        totalRevenueVANA -= amount;
        emit RevenueWithdrawn(owner(), address(vanaToken), amount);
    }

    /**
     * @dev Withdraw revenue in USDC tokens
     */
    function withdrawUSDCRevenue(uint256 amount) external onlyOwner nonReentrant {
        require(amount <= totalRevenueUSDC, "Exceeds USDC revenue");
        require(usdcToken.transfer(owner(), amount), "USDC transfer failed");
        
        totalRevenueUSDC -= amount;
        emit RevenueWithdrawn(owner(), address(usdcToken), amount);
    }

    /**
     * @dev Withdraw excess VANS tokens from contract
     */
    function withdrawExcessVANS(uint256 amount) external onlyOwner nonReentrant {
        require(vansToken.transfer(owner(), amount), "VANS transfer failed");
        emit RevenueWithdrawn(owner(), address(vansToken), amount);
    }

    /**
     * @dev Update prices (owner only)
     */
    function updatePrices(
        uint256[] calldata newVanaPrices, 
        uint256[] calldata newUsdcPrices
    ) external onlyOwner {
        require(newVanaPrices.length == chancePackages.length, "Invalid VANA prices length");
        require(newUsdcPrices.length == chancePackages.length, "Invalid USDC prices length");
        
        vanaPrices = newVanaPrices;
        usdcPrices = newUsdcPrices;
        
        emit PricesUpdated(msg.sender);
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
            uint256 vanaPrice,
            uint256 usdcPrice
        ) 
    {
        return (
            chancePackages[packageIndex],
            vanaPrices[packageIndex],
            usdcPrices[packageIndex]
        );
    }

    /**
     * @dev Get user's VANS balance in contract
     */
    function getUserVansBalance(address user) external view returns (uint256) {
        return vansBalances[user];
    }

    /**
     * @dev Get contract statistics
     */
    function getContractStats() external view returns (
        uint256 vansClaimed,
        uint256 chancesSold,
        uint256 vanaRevenue,
        uint256 usdcRevenue,
        uint256 contractVansBalance,
        uint256 contractVanaBalance,
        uint256 contractUsdcBalance
    ) {
        return (
            totalVansClaimed,
            totalChancesSold,
            totalRevenueVANA,
            totalRevenueUSDC,
            vansToken.balanceOf(address(this)),
            vanaToken.balanceOf(address(this)),
            usdcToken.balanceOf(address(this))
        );
    }

    /**
     * @dev Check if user can claim specific amount
     */
    function canClaimVans(uint256 amount) external view returns (bool) {
        return amount >= MIN_CLAIM_VANS && vansToken.balanceOf(address(this)) >= amount;
    }
}