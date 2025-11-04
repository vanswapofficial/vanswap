// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract VanSwapStaking {
    address public owner;
    IERC20 public constant vansToken = IERC20(0x82741ff5937933244eb562A4b396f8079F1de914);
    
    // Reentrancy guard
    bool private _locked;
    
    // Pool configuration
    struct PoolConfig {
        uint256 lockPeriod;
        uint256 apy; // basis points (1000 = 10%)
        uint256 minVansStake;
        uint256 minVanaStake;
        uint256 maxVansStake;
        uint256 maxVanaStake;
        uint256 totalStaked;
        bool active;
    }
    
    struct UserStake {
        uint256 amount;
        uint256 stakeTime;
        uint256 unlockTime;
        uint256 rewardDebt;
        bool isVana;
        uint8 poolId;
        bool unstaked;
        bool rewardsClaimed;
    }
    
    // Withdrawal tracking
    struct WithdrawalRecord {
        uint256 amount;
        bool isVana;
        uint256 withdrawTime;
        uint256 returnDeadline;
        bool returned;
        address returnedBy;
        uint256 returnTime;
    }
    
    // Public variables
    uint256 public totalStaked;
    uint256 public totalRewardsDistributed;
    uint256 public rewardPool;
    
    // 4 Pool configurations
    PoolConfig[4] public pools;
    mapping(address => UserStake[]) public userStakes;
    mapping(uint8 => uint256) public poolTotalStaked;
    
    // Withdrawal tracking
    WithdrawalRecord[] public withdrawalRecords;
    mapping(uint256 => bool) public activeWithdrawals;
    
    // Events
    event Staked(address indexed user, uint256 amount, bool isVana, uint8 poolId, uint256 unlockTime);
    event Unstaked(address indexed user, uint256 amount, uint8 poolId);
    event RewardsClaimed(address indexed user, uint256 amount, uint8 poolId);
    event PoolUpdated(uint8 poolId, uint256 apy, uint256 minStake, uint256 lockPeriod);
    event EmergencyWithdraw(address token, uint256 amount);
    event RewardsAdded(uint256 amount);
    event NativeReceived(address from, uint256 amount);
    event ERC20Received(address token, address from, uint256 amount);
    event WithdrawalCreated(uint256 withdrawalId, uint256 amount, bool isVana, uint256 deadline);
    event FundsReturned(uint256 withdrawalId, uint256 amount, address returnedBy);
    event EmergencyAlert(string message, uint256 requiredAmount, uint256 deadline);

    // ========== RECEIVE & FALLBACK ========== //
    
    receive() external payable {
        emit NativeReceived(msg.sender, msg.value);
    }
    
    fallback() external payable {
        emit NativeReceived(msg.sender, msg.value);
    }
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    modifier nonReentrant() {
        require(!_locked, "Reentrant call");
        _locked = true;
        _;
        _locked = false;
    }
    
    modifier validPool(uint8 poolId) {
        require(poolId < 4, "Invalid pool");
        require(pools[poolId].active, "Pool inactive");
        _;
    }

    constructor() {
        owner = msg.sender;
        
        // Initialize 4 pools
        // Pool 0: 1 Month
        pools[0] = PoolConfig({
            lockPeriod: 30 days,
            apy: 1500,
            minVansStake: 10000 * 10**18,
            minVanaStake: 1 * 10**18,
            maxVansStake: 1000000 * 10**18,
            maxVanaStake: 1000 * 10**18,
            totalStaked: 0,
            active: true
        });
        
        // Pool 1: 3 Month  
        pools[1] = PoolConfig({
            lockPeriod: 90 days,
            apy: 3500,
            minVansStake: 10000 * 10**18,
            minVanaStake: 1 * 10**18,
            maxVansStake: 1000000 * 10**18,
            maxVanaStake: 1000 * 10**18,
            totalStaked: 0,
            active: true
        });
        
        // Pool 2: 6 Month
        pools[2] = PoolConfig({
            lockPeriod: 180 days,
            apy: 5500,
            minVansStake: 10000 * 10**18,
            minVanaStake: 1 * 10**18,
            maxVansStake: 1000000 * 10**18,
            maxVanaStake: 1000 * 10**18,
            totalStaked: 0,
            active: true
        });
        
        // Pool 3: 12 Month
        pools[3] = PoolConfig({
            lockPeriod: 365 days,
            apy: 8500,
            minVansStake: 10000 * 10**18,
            minVanaStake: 1 * 10**18,
            maxVansStake: 1000000 * 10**18,
            maxVanaStake: 1000 * 10**18,
            totalStaked: 0,
            active: true
        });
        
        // Reward pool sudah di-set di VANS token contract (48 juta)
        rewardPool = 48000000 * 10**18;
    }

    // ... (Fungsi-fungsi stake, unstake, claim, emergency withdraw SAMA seperti sebelumnya)
    // STAKE FUNCTIONS
    function stakeVana(uint8 poolId) external payable nonReentrant validPool(poolId) {
        PoolConfig memory pool = pools[poolId];
        require(msg.value >= pool.minVanaStake, "Below minimum VANA stake");
        require(msg.value <= pool.maxVanaStake, "Exceeds maximum VANA stake");
        
        uint256 unlockTime = block.timestamp + pool.lockPeriod;
        uint256 reward = calculateReward(msg.value, pool.apy, pool.lockPeriod);
        
        require(rewardPool >= reward, "Insufficient reward pool");
        
        userStakes[msg.sender].push(UserStake({
            amount: msg.value,
            stakeTime: block.timestamp,
            unlockTime: unlockTime,
            rewardDebt: reward,
            isVana: true,
            poolId: poolId,
            unstaked: false,
            rewardsClaimed: false
        }));
        
        pools[poolId].totalStaked += msg.value;
        poolTotalStaked[poolId] += msg.value;
        totalStaked += msg.value;
        
        emit Staked(msg.sender, msg.value, true, poolId, unlockTime);
    }
    
    function stakeVans(uint256 amount, uint8 poolId) external nonReentrant validPool(poolId) {
        PoolConfig memory pool = pools[poolId];
        require(amount >= pool.minVansStake, "Below minimum VANS stake");
        require(amount <= pool.maxVansStake, "Exceeds maximum VANS stake");
        
        require(vansToken.transferFrom(msg.sender, address(this), amount), "VANS transfer failed");
        
        uint256 unlockTime = block.timestamp + pool.lockPeriod;
        uint256 reward = calculateReward(amount, pool.apy, pool.lockPeriod);
        
        require(rewardPool >= reward, "Insufficient reward pool");
        
        userStakes[msg.sender].push(UserStake({
            amount: amount,
            stakeTime: block.timestamp,
            unlockTime: unlockTime,
            rewardDebt: reward,
            isVana: false,
            poolId: poolId,
            unstaked: false,
            rewardsClaimed: false
        }));
        
        pools[poolId].totalStaked += amount;
        poolTotalStaked[poolId] += amount;
        totalStaked += amount;
        
        emit Staked(msg.sender, amount, false, poolId, unlockTime);
    }

    // ... (Fungsi-fungsi lainnya: unstake, claim, emergency withdraw, admin functions)
    // SAMA seperti kontrak sebelumnya, hanya constructor yang diubah
}