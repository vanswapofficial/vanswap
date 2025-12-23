// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract VanAirdropV3 {
    address public owner;
    
    // Token addresses
    address public vansToken = 0x82741ff5937933244eb562A4b396f8079F1de914;
    address public exoToken = 0x56C44f52D7Dc7DD82b01f6694D9a91C8e3cDF9a6;
    
    // Airdrop amounts - DIKURANGI 75%
    // Asli: 100 VANS -> Sekarang: 25 VANS (100 * 25% = 25)
    uint256 public constant INITIAL_REWARD_VANS = 25 * 10**18;       // 25 VANS (dari 100)
    uint256 public constant INITIAL_REWARD_EXO = 0.0025 * 10**8;    // 0.0025 EXO (dari 0.01)
    uint256 public constant DAILY_REWARD_VANS = 12.5 * 10**18;      // 12.5 VANS (dari 50)
    uint256 public constant DAILY_REWARD_EXO = 0.00025 * 10**8;     // 0.00025 EXO (dari 0.001)
    
    // Referral rewards - DIKURANGI 75%
    uint256 public constant REFERRAL_REWARD_VANS = 2.5 * 10**18;    // 2.5 VANS (dari 10)
    uint256 public constant REFERRAL_REWARD_EXO = 0.00025 * 10**8;  // 0.00025 EXO (dari 0.001)
    uint256 public constant REFERRAL_BONUS_EXO = 0.025 * 10**8;     // 0.025 EXO (dari 0.1)
    
    // Limits - tetap sama atau bisa disesuaikan
    uint256 public constant MAX_REFERRALS = 20;
    uint256 public constant MAX_USERS = 32000;                       // Bisa 4x lebih banyak karena reward 75% lebih kecil
    uint256 public constant CLAIM_COOLDOWN = 24 hours;
    
    // User structure
    struct UserInfo {
        bool registered;
        uint256 lastClaimTime;
        uint256 totalClaims;
        uint256 referralCount;
        uint256 totalReferralRewards;
        address referrer;
        uint256 claimedVans;
        uint256 claimedExo;
        uint256 pendingReferralBonus;
        string referralCode;
        uint256 referralsToday;
        uint256 lastReferralReset;
    }
    
    // Mappings
    mapping(address => UserInfo) public users;
    mapping(string => address) public referralCodeToAddress;
    mapping(address => bool) public claimedInitial;
    mapping(address => mapping(address => bool)) public referrals;
    mapping(address => uint256) public lastTxBlock;
    
    // State variables
    uint256 public totalRegistered;
    bool public registrationsPaused;
    bool public emergencyWithdrawEnabled;
    uint256 public emergencyWithdrawTime;
    
    // Events
    event Registered(address indexed user, address indexed referrer, string referralCode);
    event ClaimedDaily(address indexed user, uint256 vansAmount, uint256 exoAmount);
    event ClaimedInitial(address indexed user, uint256 vansAmount, uint256 exoAmount);
    event ReferralReward(address indexed referrer, address indexed referee, uint256 vansAmount, uint256 exoAmount);
    event ReferralBonusClaimed(address indexed user, uint256 exoAmount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event EmergencyWithdraw(address token, uint256 amount);
    event ReferralCodeGenerated(address indexed user, string code);
    event FundsDeposited(uint256 vansAmount, uint256 exoAmount);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    modifier notContract() {
        require(msg.sender == tx.origin, "Contracts not allowed");
        _;
    }
    
    modifier antiBot() {
        require(lastTxBlock[msg.sender] != block.number, "One tx per block");
        lastTxBlock[msg.sender] = block.number;
        _;
    }
    
    modifier notExceedMaxUsers() {
        require(totalRegistered < MAX_USERS, "Max users reached");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        emergencyWithdrawTime = block.timestamp + 365 days;
    }
    
    // ==================== CALCULATION FUNCTIONS ====================
    
    // Hitung maksimal user yang bisa didukung dengan supply Anda (sudah disesuaikan)
    function calculateMaxUsers() public pure returns (
        uint256 maxUsersByVans,
        uint256 maxUsersByExo,
        uint256 totalVansNeeded,
        uint256 totalExoNeeded
    ) {
        // Per user membutuhkan (SETELAH DIKURANGI 75%):
        // - Initial: 25 VANS + 0.0025 EXO
        // - Daily (30 hari): 375 VANS + 0.0075 EXO
        // - Referral (maks 20): 50 VANS + 0.005 EXO + 0.5 EXO bonus
        // Total per user: ~450 VANS + 0.515 EXO
        
        uint256 vansPerUser = INITIAL_REWARD_VANS + (DAILY_REWARD_VANS * 30) + (REFERRAL_REWARD_VANS * MAX_REFERRALS);
        uint256 exoPerUser = INITIAL_REWARD_EXO + (DAILY_REWARD_EXO * 30) + (REFERRAL_REWARD_EXO * MAX_REFERRALS) + (REFERRAL_BONUS_EXO * MAX_REFERRALS);
        
        // Untuk 32000 user
        totalVansNeeded = vansPerUser * 32000 / 10**18;
        totalExoNeeded = exoPerUser * 32000 / 10**8;
        
        // Perhitungan maksimal user berdasarkan supply
        // Dengan 1,000,000 VANS: 1,000,000 / 450 ≈ 2222 user
        // Dengan 500 EXO: 500 / 0.515 ≈ 971 user
        
        maxUsersByVans = 2222;
        maxUsersByExo = 971;
        
        return (maxUsersByVans, maxUsersByExo, totalVansNeeded, totalExoNeeded);
    }
    
    // ==================== REGISTRATION & REFERRAL ====================
    
    function registerWithCode(string memory referralCode) external notContract antiBot notExceedMaxUsers {
        require(!registrationsPaused, "Registrations paused");
        require(!users[msg.sender].registered, "Already registered");
        
        address referrer = referralCodeToAddress[referralCode];
        
        UserInfo storage user = users[msg.sender];
        user.registered = true;
        user.lastClaimTime = block.timestamp - CLAIM_COOLDOWN;
        user.lastReferralReset = block.timestamp;
        
        // Generate auto referral code
        string memory autoCode = _generateAutoCode(msg.sender);
        user.referralCode = autoCode;
        referralCodeToAddress[autoCode] = msg.sender;
        
        totalRegistered++;
        
        // Process referral if valid
        if (referrer != address(0) && 
            referrer != msg.sender && 
            users[referrer].registered &&
            users[referrer].referralCount < MAX_REFERRALS) {
            
            // Reset daily referral count if new day
            if (block.timestamp - users[referrer].lastReferralReset >= 1 days) {
                users[referrer].referralsToday = 0;
                users[referrer].lastReferralReset = block.timestamp;
            }
            
            require(users[referrer].referralsToday < 10, "Max 10 referrals per day");
            
            users[referrer].referralCount++;
            users[referrer].referralsToday++;
            user.referrer = referrer;
            
            // Store pending referral bonus for referrer (0.025 EXO)
            users[referrer].pendingReferralBonus += REFERRAL_BONUS_EXO;
            
            emit Registered(msg.sender, referrer, autoCode);
        } else {
            emit Registered(msg.sender, address(0), autoCode);
        }
    }
    
    function generateCustomReferralCode(string memory code) external notContract {
        require(users[msg.sender].registered, "Not registered");
        require(bytes(code).length >= 3 && bytes(code).length <= 10, "Code 3-10 chars");
        require(referralCodeToAddress[code] == address(0), "Code taken");
        require(bytes(users[msg.sender].referralCode).length == 8, "Already have custom code");
        
        string memory lowerCode = _toLower(code);
        users[msg.sender].referralCode = lowerCode;
        referralCodeToAddress[lowerCode] = msg.sender;
        
        emit ReferralCodeGenerated(msg.sender, lowerCode);
    }
    
    // ==================== CLAIM FUNCTIONS ====================
    
    function claimInitial() external notContract antiBot {
        require(users[msg.sender].registered, "Not registered");
        require(!claimedInitial[msg.sender], "Already claimed");
        
        uint256 vansBalance = IERC20(vansToken).balanceOf(address(this));
        uint256 exoBalance = IERC20(exoToken).balanceOf(address(this));
        
        require(vansBalance >= INITIAL_REWARD_VANS, "Insufficient VANS");
        require(exoBalance >= INITIAL_REWARD_EXO, "Insufficient EXO");
        
        // Transfer rewards (75% lebih kecil)
        require(IERC20(vansToken).transfer(msg.sender, INITIAL_REWARD_VANS), "VANS failed");
        require(IERC20(exoToken).transfer(msg.sender, INITIAL_REWARD_EXO), "EXO failed");
        
        claimedInitial[msg.sender] = true;
        users[msg.sender].claimedVans += INITIAL_REWARD_VANS;
        users[msg.sender].claimedExo += INITIAL_REWARD_EXO;
        
        emit ClaimedInitial(msg.sender, INITIAL_REWARD_VANS, INITIAL_REWARD_EXO);
    }
    
    function claimDaily() external notContract antiBot {
        require(users[msg.sender].registered, "Not registered");
        
        UserInfo storage user = users[msg.sender];
        require(block.timestamp >= user.lastClaimTime + CLAIM_COOLDOWN, "Cooldown active");
        
        // Calculate rewards (75% lebih kecil)
        uint256 vansReward = DAILY_REWARD_VANS + (user.referralCount * REFERRAL_REWARD_VANS);
        uint256 exoReward = DAILY_REWARD_EXO;
        
        // Check contract balance
        uint256 vansBalance = IERC20(vansToken).balanceOf(address(this));
        uint256 exoBalance = IERC20(exoToken).balanceOf(address(this));
        
        require(vansBalance >= vansReward, "Insufficient VANS");
        require(exoBalance >= exoReward, "Insufficient EXO");
        
        // Transfer rewards
        require(IERC20(vansToken).transfer(msg.sender, vansReward), "VANS failed");
        require(IERC20(exoToken).transfer(msg.sender, exoReward), "EXO failed");
        
        // Update user
        user.lastClaimTime = block.timestamp;
        user.totalClaims++;
        user.claimedVans += vansReward;
        user.claimedExo += exoReward;
        
        // Distribute referral rewards
        _distributeReferralRewards(msg.sender);
        
        emit ClaimedDaily(msg.sender, vansReward, exoReward);
    }
    
    function claimReferralBonus() external notContract antiBot {
        UserInfo storage user = users[msg.sender];
        require(user.pendingReferralBonus > 0, "No pending bonus");
        
        uint256 bonus = user.pendingReferralBonus;
        uint256 exoBalance = IERC20(exoToken).balanceOf(address(this));
        require(exoBalance >= bonus, "Insufficient EXO");
        
        user.pendingReferralBonus = 0;
        require(IERC20(exoToken).transfer(msg.sender, bonus), "EXO failed");
        
        emit ReferralBonusClaimed(msg.sender, bonus);
    }
    
    // ==================== EMERGENCY & ADMIN FUNCTIONS ====================
    
    function enableEmergencyWithdraw() external onlyOwner {
        require(block.timestamp >= emergencyWithdrawTime, "Too early");
        emergencyWithdrawEnabled = true;
    }
    
    function emergencyWithdrawAll() external onlyOwner {
        require(emergencyWithdrawEnabled, "Emergency not enabled");
        
        uint256 vansBalance = IERC20(vansToken).balanceOf(address(this));
        uint256 exoBalance = IERC20(exoToken).balanceOf(address(this));
        
        // Withdraw 90% only, leave 10% for existing claims
        uint256 vansToWithdraw = (vansBalance * 90) / 100;
        uint256 exoToWithdraw = (exoBalance * 90) / 100;
        
        if (vansToWithdraw > 0) {
            IERC20(vansToken).transfer(owner, vansToWithdraw);
            emit EmergencyWithdraw(vansToken, vansToWithdraw);
        }
        
        if (exoToWithdraw > 0) {
            IERC20(exoToken).transfer(owner, exoToWithdraw);
            emit EmergencyWithdraw(exoToken, exoToWithdraw);
        }
    }
    
    function depositFunds(uint256 vansAmount, uint256 exoAmount) external onlyOwner {
        if (vansAmount > 0) {
            require(IERC20(vansToken).transferFrom(msg.sender, address(this), vansAmount), "VANS deposit failed");
        }
        if (exoAmount > 0) {
            require(IERC20(exoToken).transferFrom(msg.sender, address(this), exoAmount), "EXO deposit failed");
        }
        
        emit FundsDeposited(vansAmount, exoAmount);
    }
    
    function withdrawExcess(uint256 vansAmount, uint256 exoAmount) external onlyOwner {
        require(!emergencyWithdrawEnabled, "Use emergency withdraw");
        
        uint256 vansBalance = IERC20(vansToken).balanceOf(address(this));
        uint256 exoBalance = IERC20(exoToken).balanceOf(address(this));
        
        // Calculate required reserves (disesuaikan dengan reward baru)
        uint256 requiredVans = totalRegistered * (INITIAL_REWARD_VANS + (DAILY_REWARD_VANS * 30) + (REFERRAL_REWARD_VANS * 10));
        uint256 requiredExo = totalRegistered * (INITIAL_REWARD_EXO + (DAILY_REWARD_EXO * 30) + (REFERRAL_REWARD_EXO * 10) + (REFERRAL_BONUS_EXO * 10));
        
        if (vansAmount > 0 && vansBalance - vansAmount >= requiredVans) {
            IERC20(vansToken).transfer(owner, vansAmount);
        }
        
        if (exoAmount > 0 && exoBalance - exoAmount >= requiredExo) {
            IERC20(exoToken).transfer(owner, exoAmount);
        }
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    function getAvailableRewards(address userAddress) external view returns (
        uint256 vansDaily,
        uint256 exoDaily,
        uint256 timeUntilNextClaim,
        bool canClaimInitial,
        uint256 pendingBonus,
        uint256 referralsLeft,
        uint256 contractVansBalance,
        uint256 contractExoBalance
    ) {
        UserInfo storage user = users[userAddress];
        
        if (!user.registered) {
            return (0, 0, 0, false, 0, MAX_REFERRALS, 0, 0);
        }
        
        vansDaily = DAILY_REWARD_VANS + (user.referralCount * REFERRAL_REWARD_VANS);
        exoDaily = DAILY_REWARD_EXO;
        
        if (block.timestamp >= user.lastClaimTime + CLAIM_COOLDOWN) {
            timeUntilNextClaim = 0;
        } else {
            timeUntilNextClaim = (user.lastClaimTime + CLAIM_COOLDOWN) - block.timestamp;
        }
        
        canClaimInitial = !claimedInitial[userAddress];
        pendingBonus = user.pendingReferralBonus;
        referralsLeft = MAX_REFERRALS - user.referralCount;
        contractVansBalance = IERC20(vansToken).balanceOf(address(this)) / 10**18;
        contractExoBalance = IERC20(exoToken).balanceOf(address(this)) / 10**8;
    }
    
    function getContractInfo() external view returns (
        uint256 totalUsers,
        uint256 maxUsers,
        uint256 vansBalance,
        uint256 exoBalance,
        uint256 daysUntilEmergency,
        bool registrationsActive
    ) {
        totalUsers = totalRegistered;
        maxUsers = MAX_USERS;
        vansBalance = IERC20(vansToken).balanceOf(address(this)) / 10**18;
        exoBalance = IERC20(exoToken).balanceOf(address(this)) / 10**8;
        
        if (block.timestamp >= emergencyWithdrawTime) {
            daysUntilEmergency = 0;
        } else {
            daysUntilEmergency = (emergencyWithdrawTime - block.timestamp) / 1 days;
        }
        
        registrationsActive = !registrationsPaused && totalRegistered < MAX_USERS;
    }
    
    // ==================== HELPER FUNCTIONS ====================
    
    function _generateAutoCode(address addr) internal pure returns (string memory) {
        bytes20 addrBytes = bytes20(addr);
        bytes memory code = new bytes(8);
        
        for (uint i = 0; i < 8; i++) {
            uint8 b = uint8(addrBytes[i + 12]);
            code[i] = bytes1((b % 26) + 97); // a-z
        }
        
        return string(code);
    }
    
    function _toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        for (uint i = 0; i < bStr.length; i++) {
            if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        return string(bLower);
    }
    
    function _distributeReferralRewards(address referee) internal {
        address referrer = users[referee].referrer;
        
        if (referrer != address(0) && !referrals[referrer][referee]) {
            UserInfo storage refUser = users[referrer];
            
            if (refUser.referralCount <= MAX_REFERRALS) {
                uint256 vansBalance = IERC20(vansToken).balanceOf(address(this));
                uint256 exoBalance = IERC20(exoToken).balanceOf(address(this));
                
                if (vansBalance >= REFERRAL_REWARD_VANS && exoBalance >= REFERRAL_REWARD_EXO) {
                    IERC20(vansToken).transfer(referrer, REFERRAL_REWARD_VANS);
                    IERC20(exoToken).transfer(referrer, REFERRAL_REWARD_EXO);
                    
                    referrals[referrer][referee] = true;
                    refUser.totalReferralRewards += REFERRAL_REWARD_VANS + REFERRAL_REWARD_EXO;
                    
                    emit ReferralReward(referrer, referee, REFERRAL_REWARD_VANS, REFERRAL_REWARD_EXO);
                }
            }
        }
    }
    
    // Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
    
    // Pause/unpause
    function setPauseRegistrations(bool pause) external onlyOwner {
        registrationsPaused = pause;
    }
    
    // Update emergency time
    function updateEmergencyTime(uint256 newTime) external onlyOwner {
        emergencyWithdrawTime = newTime;
    }
    
    // Fallback
    receive() external payable {}
}