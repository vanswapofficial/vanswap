// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract vUSD is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint8 private constant DECIMALS = 6;
    uint256 private constant INITIAL_SUPPLY = 100_000 * 10 ** 6; // 100,000 vUSD untuk owner
    uint256 private constant MIN_DEPOSIT = 10 * 10 ** 6; // $10
    uint256 private constant MAX_DEPOSIT = 1_000_000 * 10 ** 6; // $1M

    struct StablecoinInfo {
        IERC20 token;
        uint256 trackedReserve; // Reserve yang tercatat
        uint256 actualReserve;  // Balance aktual terakhir diverifikasi
        uint8 decimals;
        bool isActive;
        uint256 totalDeposits;
        uint256 totalWithdrawals;
        string symbol;
    }

    mapping(address => StablecoinInfo) public stablecoins;
    address[] public activeStablecoins;

    // Security state
    bool public paused;
    bool private initialMinted;

    // Events dengan lebih banyak detail
    event Deposited(
        address indexed user, 
        address indexed stablecoin, 
        uint256 stableAmount, 
        uint256 vusdAmount,
        uint256 newReserve
    );
    event Redeemed(
        address indexed user, 
        address indexed stablecoin, 
        uint256 vusdAmount, 
        uint256 stableAmount,
        uint256 newReserve
    );
    event StablecoinAdded(address indexed stablecoin, uint8 decimals, string symbol);
    event StablecoinUpdated(address indexed stablecoin, bool isActive);
    event EmergencyPause(bool paused);
    event ReserveSynced(address indexed stablecoin, uint256 tracked, uint256 actual, bool matched);
    event AdminWithdraw(address indexed stablecoin, uint256 amount, address to);

    modifier whenNotPaused() {
        require(!paused, "Contract paused");
        _;
    }

    modifier validStablecoin(address _stablecoin) {
        require(_stablecoin != address(0), "Invalid address");
        require(stablecoins[_stablecoin].isActive, "Stablecoin not supported");
        _;
    }

    modifier onlyInitialMintNotDone() {
        require(!initialMinted, "Initial supply already minted");
        _;
    }

    constructor() ERC20("Virtual USD", "vUSD") Ownable(msg.sender) {
        // Langsung mint initial supply ke owner
        _mint(msg.sender, INITIAL_SUPPLY);
        initialMinted = true;
        paused = false;
    }

    // =================== STABLECOIN MANAGEMENT ===================

    function addStablecoin(address _stablecoin) external onlyOwner {
        require(_stablecoin != address(0), "Invalid address");
        require(!stablecoins[_stablecoin].isActive, "Already added");

        IERC20 token = IERC20(_stablecoin);

        // Verifikasi contract adalah ERC20 yang valid
        try token.totalSupply() {
            // Success
        } catch {
            revert("Not a valid ERC20");
        }

        // Ambil decimals
        uint8 tokenDecimals;
        try token.decimals() returns (uint8 decimals) {
            tokenDecimals = decimals;
        } catch {
            revert("Must implement decimals()");
        }

        require(tokenDecimals == 6, "Only 6 decimals supported"); // USDT/USDC standard

        // Ambil symbol
        string memory tokenSymbol;
        try token.symbol() returns (string memory symbol) {
            tokenSymbol = symbol;
        } catch {
            tokenSymbol = "UNKNOWN";
        }

        // Test transfer
        try token.transfer(address(this), 0) returns (bool success) {
            require(success, "Transfer test failed");
        } catch {
            revert("Transfer function failed");
        }

        stablecoins[_stablecoin] = StablecoinInfo({
            token: token,
            trackedReserve: 0,
            actualReserve: 0,
            decimals: tokenDecimals,
            isActive: true,
            totalDeposits: 0,
            totalWithdrawals: 0,
            symbol: tokenSymbol
        });

        activeStablecoins.push(_stablecoin);
        emit StablecoinAdded(_stablecoin, tokenDecimals, tokenSymbol);
    }

    function updateStablecoinStatus(address _stablecoin, bool _isActive) external onlyOwner {
        require(_stablecoin != address(0), "Invalid address");
        require(stablecoins[_stablecoin].token != IERC20(address(0)), "Stablecoin not found");

        // Jika menonaktifkan, pastikan reserve kosong
        if (!_isActive) {
            require(
                stablecoins[_stablecoin].trackedReserve == 0,
                "Cannot deactivate with reserve"
            );
            require(
                stablecoins[_stablecoin].token.balanceOf(address(this)) == 0,
                "Cannot deactivate with balance"
            );
        }

        stablecoins[_stablecoin].isActive = _isActive;
        emit StablecoinUpdated(_stablecoin, _isActive);
    }

    // =================== PUBLIC DEPOSIT FUNCTION ===================

    function deposit(address _stablecoin, uint256 _amount) 
        external 
        nonReentrant 
        whenNotPaused 
        validStablecoin(_stablecoin)
        returns (uint256 vusdAmount)
    {
        require(_amount >= MIN_DEPOSIT, "Below minimum deposit");
        require(_amount <= MAX_DEPOSIT, "Above maximum deposit");

        StablecoinInfo storage info = stablecoins[_stablecoin];

        // Dapatkan balance sebelum transfer
        uint256 balanceBefore = info.token.balanceOf(address(this));

        // Transfer dengan safeTransferFrom
        info.token.safeTransferFrom(msg.sender, address(this), _amount);

        // Dapatkan balance setelah transfer
        uint256 balanceAfter = info.token.balanceOf(address(this));

        // Hitung amount yang benar-benar diterima
        uint256 actualReceived = balanceAfter - balanceBefore;
        require(actualReceived > 0, "No tokens received");
        require(actualReceived >= _amount * 99 / 100, "Received less than 99%"); // Allow 1% fee max

        // Hitung vUSD amount (1:1 karena decimals sama = 6)
        vusdAmount = actualReceived; // USDT/USDC sudah 6 decimals

        require(vusdAmount > 0, "vUSD amount too small");

        // UPDATE STATE (Checks-Effects-Interactions pattern)
        info.trackedReserve += actualReceived;
        info.actualReserve = balanceAfter; // Sync dengan balance aktual
        info.totalDeposits += actualReceived;

        // Mint vUSD ke user
        _mint(msg.sender, vusdAmount);

        // Verifikasi supply tetap backed
        require(
            getTotalTrackedReserve() >= totalSupply() - balanceOf(owner()),
            "Reserve insufficient after mint"
        );

        emit Deposited(msg.sender, _stablecoin, actualReceived, vusdAmount, info.trackedReserve);
    }

    // =================== PUBLIC REDEEM FUNCTION ===================

    function redeem(address _stablecoin, uint256 _vusdAmount, uint256 _minStableAmount) 
        external 
        nonReentrant 
        whenNotPaused 
        validStablecoin(_stablecoin)
        returns (uint256 stableAmount)
    {
        require(_vusdAmount > 0, "Amount must be > 0");
        require(balanceOf(msg.sender) >= _vusdAmount, "Insufficient vUSD");

        StablecoinInfo storage info = stablecoins[_stablecoin];

        // Convert vUSD to stablecoin amount (1:1 karena decimals sama)
        stableAmount = _vusdAmount;

        require(stableAmount > 0, "Stable amount too small");

        // Slippage protection
        require(stableAmount >= _minStableAmount, "Slippage too high");

        // DOUBLE VERIFICATION: Cek reserve tercatat DAN balance aktual
        require(info.trackedReserve >= stableAmount, "Insufficient tracked reserve");

        uint256 currentBalance = info.token.balanceOf(address(this));
        require(currentBalance >= stableAmount, "Insufficient actual balance");

        // CHECKS-EFFECTS-INTERACTIONS pattern
        // 1. Burn vUSD dari user
        _burn(msg.sender, _vusdAmount);

        // 2. Update state
        info.trackedReserve -= stableAmount;
        info.totalWithdrawals += stableAmount;

        // 3. Transfer stablecoin ke user
        info.token.safeTransfer(msg.sender, stableAmount);

        // 4. Update actual reserve setelah transfer
        info.actualReserve = info.token.balanceOf(address(this));

        emit Redeemed(msg.sender, _stablecoin, _vusdAmount, stableAmount, info.trackedReserve);
    }

    // =================== SECURITY & ADMIN FUNCTIONS ===================

    function emergencyPause() external onlyOwner {
        paused = true;
        emit EmergencyPause(true);
    }

    function emergencyUnpause() external onlyOwner {
        paused = false;
        emit EmergencyPause(false);
    }

    // Sync reserve dengan balance aktual
    function syncReserve(address _stablecoin) external validStablecoin(_stablecoin) {
        StablecoinInfo storage info = stablecoins[_stablecoin];
        uint256 currentBalance = info.token.balanceOf(address(this));

        bool matched = (info.trackedReserve == currentBalance);

        if (!matched) {
            // Jika ada discrepancy, gunakan nilai yang lebih kecil untuk safety
            if (currentBalance < info.trackedReserve) {
                info.trackedReserve = currentBalance;
            }
            info.actualReserve = currentBalance;
        }

        emit ReserveSynced(_stablecoin, info.trackedReserve, currentBalance, matched);
    }

    // Emergency withdraw hanya untuk owner dan hanya saat paused
    function emergencyWithdraw(address _stablecoin, address _to) external onlyOwner {
        require(paused, "Only when paused");
        require(_to != address(0), "Invalid recipient");

        StablecoinInfo storage info = stablecoins[_stablecoin];
        require(info.isActive, "Stablecoin not active");

        uint256 balance = info.token.balanceOf(address(this));
        require(balance > 0, "No balance");

        // Reset semua state
        info.trackedReserve = 0;
        info.actualReserve = 0;
        info.isActive = false;

        // Transfer semua balance
        info.token.safeTransfer(_to, balance);

        emit AdminWithdraw(_stablecoin, balance, _to);
        emit StablecoinUpdated(_stablecoin, false);
    }

    // Remove inactive stablecoin dari array (hanya owner)
    function cleanInactiveStablecoins() external onlyOwner {
        uint256 i = 0;
        while (i < activeStablecoins.length) {
            if (!stablecoins[activeStablecoins[i]].isActive) {
                // Swap dengan element terakhir dan pop
                activeStablecoins[i] = activeStablecoins[activeStablecoins.length - 1];
                activeStablecoins.pop();
            } else {
                i++;
            }
        }
    }

    // =================== VIEW FUNCTIONS ===================

    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    function getStablecoinInfo(address _stablecoin) public view returns (
        string memory symbol,
        uint8 decimals,
        uint256 trackedReserve,
        uint256 actualBalance,
        uint256 totalDeposits,
        uint256 totalWithdrawals,
        bool isActive
    ) {
        StablecoinInfo memory info = stablecoins[_stablecoin];
        return (
            info.symbol,
            info.decimals,
            info.trackedReserve,
            info.token.balanceOf(address(this)),
            info.totalDeposits,
            info.totalWithdrawals,
            info.isActive
        );
    }

    function getTotalTrackedReserve() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < activeStablecoins.length; i++) {
            address tokenAddr = activeStablecoins[i];
            if (stablecoins[tokenAddr].isActive) {
                total += stablecoins[tokenAddr].trackedReserve;
            }
        }
        return total;
    }

    function getTotalActualReserve() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < activeStablecoins.length; i++) {
            address tokenAddr = activeStablecoins[i];
            if (stablecoins[tokenAddr].isActive) {
                total += stablecoins[tokenAddr].token.balanceOf(address(this));
            }
        }
        return total;
    }

    function getAllActiveStablecoins() public view returns (
        address[] memory addresses,
        string[] memory symbols,
        uint256[] memory reserves
    ) {
        uint256 activeCount = 0;

        // Hitung yang aktif dulu
        for (uint256 i = 0; i < activeStablecoins.length; i++) {
            if (stablecoins[activeStablecoins[i]].isActive) {
                activeCount++;
            }
        }

        addresses = new address[](activeCount);
        symbols = new string[](activeCount);
        reserves = new uint256[](activeCount);

        uint256 index = 0;
        for (uint256 i = 0; i < activeStablecoins.length; i++) {
            address tokenAddr = activeStablecoins[i];
            if (stablecoins[tokenAddr].isActive) {
                addresses[index] = tokenAddr;
                symbols[index] = stablecoins[tokenAddr].symbol;
                reserves[index] = stablecoins[tokenAddr].trackedReserve;
                index++;
            }
        }
    }

    function isFullyBacked() public view returns (bool) {
        uint256 totalReserve = getTotalTrackedReserve();
        uint256 circulatingSupply = totalSupply() - balanceOf(owner());
        return totalReserve >= circulatingSupply;
    }

    function getHealthStatus() public view returns (
        bool fullyBacked,
        uint256 circulatingSupply,
        uint256 totalTrackedReserve,
        uint256 totalActualBalance,
        bool reservesSynced,
        uint256 backingRatio
    ) {
        circulatingSupply = totalSupply() - balanceOf(owner());
        totalTrackedReserve = getTotalTrackedReserve();
        totalActualBalance = getTotalActualReserve();
        fullyBacked = totalTrackedReserve >= circulatingSupply;
        reservesSynced = totalTrackedReserve == totalActualBalance;

        if (circulatingSupply > 0) {
            backingRatio = (totalTrackedReserve * 100) / circulatingSupply;
        } else {
            backingRatio = type(uint256).max;
        }
    }

    // =================== OVERRIDES ===================

    function transfer(address to, uint256 amount) 
        public 
        override 
        whenNotPaused 
        returns (bool) 
    {
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) 
        public 
        override 
        whenNotPaused 
        returns (bool) 
    {
        return super.transferFrom(from, to, amount);
    }

    // Prevent direct ETH transfers
    receive() external payable {
        revert("Direct ETH transfers not allowed");
    }

    fallback() external payable {
        revert("Invalid function call");
    }
}