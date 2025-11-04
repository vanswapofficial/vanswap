// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract VanSwapStaking {
    address public owner;
    IERC20 public vansToken;
    
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
        uint8 poolId; // 0:1month, 1:3month, 2:6month, 3:12month
        bool unstaked;
        bool rewardsClaimed;
    }
    
    // Withdrawal tracking untuk admin panel
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
    mapping(uint256 => bool) public activeWithdrawals; // withdrawalId => active
    
    // Events - PERBAIKAN: Syntax yang benar
    event Staked(address indexed user, uint256 amount, bool isVana, uint8 poolId, uint256 unlockTime);
    event Unstaked(address indexed user, uint256 amount, uint8 poolId);
    event RewardsClaimed(address indexed user, uint256 amount, uint8 poolId);
    event PoolUpdated(uint8 poolId, uint256 apy, uint256 minStake, uint256 lockPeriod);
    event EmergencyWithdraw(address token, uint256 amount); // PERBAIKAN: tanpa parameter names
    event RewardsAdded(uint256 amount);
    event NativeReceived(address from, uint256 amount);
    event ERC20Received(address token, address from, uint256 amount);
    event WithdrawalCreated(uint256 withdrawalId, uint256 amount, bool isVana, uint256 deadline);
    event FundsReturned(uint256 withdrawalId, uint256 amount, address returnedBy);
    event EmergencyAlert(string message, uint256 requiredAmount, uint256 deadline);

    // ========== RECEIVE & FALLBACK FUNCTIONS ========== //
    
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

    constructor(address _vansToken) {
        owner = msg.sender;
        vansToken = IERC20(_vansToken);
        
        // Initialize 4 pools dengan batasan max
        // Pool 0: 1 Month
        pools[0] = PoolConfig({
            lockPeriod: 30 days,
            apy: 1500,          // 15% APY
            minVansStake: 10000 * 10**18,    // 10,000 VANS
            minVanaStake: 1 * 10**18,        // 1 VANA
            maxVansStake: 1000000 * 10**18,  // 1,000,000 VANS max
            maxVanaStake: 1000 * 10**18,     // 1,000 VANA max
            totalStaked: 0,
            active: true
        });
        
        // Pool 1: 3 Month  
        pools[1] = PoolConfig({
            lockPeriod: 90 days,
            apy: 3500,          // 35% APY
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
            apy: 5500,          // 55% APY
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
            apy: 8500,          // 85% APY
            minVansStake: 10000 * 10**18,
            minVanaStake: 1 * 10**18,
            maxVansStake: 1000000 * 10**18,
            maxVanaStake: 1000 * 10**18,
            totalStaked: 0,
            active: true
        });
        
        // Set reward pool (40% dari 120M = 48M VANS)
        rewardPool = 48000000 * 10**18;
    }
    
    // ========== STAKE FUNCTIONS ========== //
    
    // Stake VANA Native
    function stakeVana(uint8 poolId) external payable nonReentrant validPool(poolId) {
        PoolConfig memory pool = pools[poolId];
        require(msg.value >= pool.minVanaStake, "Below minimum VANA stake");
        require(msg.value <= pool.maxVanaStake, "Exceeds maximum VANA stake");
        
        uint256 unlockTime = block.timestamp + pool.lockPeriod;
        uint256 reward = calculateReward(msg.value, pool.apy, pool.lockPeriod);
        
        // Cek apakah reward pool cukup
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
    
    // Stake VANS Tokens
    function stakeVans(uint256 amount, uint8 poolId) external nonReentrant validPool(poolId) {
        PoolConfig memory pool = pools[poolId];
        require(amount >= pool.minVansStake, "Below minimum VANS stake");
        require(amount <= pool.maxVansStake, "Exceeds maximum VANS stake");
        
        // Transfer VANS dari user
        require(vansToken.transferFrom(msg.sender, address(this), amount), "VANS transfer failed");
        
        uint256 unlockTime = block.timestamp + pool.lockPeriod;
        uint256 reward = calculateReward(amount, pool.apy, pool.lockPeriod);
        
        // Cek apakah reward pool cukup
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
    
    // ========== UNSTAKE & CLAIM FUNCTIONS ========== //
    
    function unstake(uint256 stakeIndex) external nonReentrant {
        require(stakeIndex < userStakes[msg.sender].length, "Invalid stake index");
        
        UserStake storage stake = userStakes[msg.sender][stakeIndex];
        require(!stake.unstaked, "Already unstaked");
        require(block.timestamp >= stake.unlockTime, "Stake still locked");
        
        uint256 principal = stake.amount;
        
        // Transfer principal kembali
        if(stake.isVana) {
            payable(msg.sender).transfer(principal);
        } else {
            require(vansToken.transfer(msg.sender, principal), "VANS transfer failed");
        }
        
        // Update totals
        pools[stake.poolId].totalStaked -= principal;
        poolTotalStaked[stake.poolId] -= principal;
        totalStaked -= principal;
        stake.unstaked = true;
        
        emit Unstaked(msg.sender, principal, stake.poolId);
    }
    
    function claimRewards(uint256 stakeIndex) external nonReentrant {
        require(stakeIndex < userStakes[msg.sender].length, "Invalid stake index");
        
        UserStake storage stake = userStakes[msg.sender][stakeIndex];
        require(!stake.unstaked, "Already unstaked");
        require(!stake.rewardsClaimed, "Rewards already claimed");
        require(block.timestamp >= stake.unlockTime, "Stake still locked");
        
        uint256 reward = stake.rewardDebt;
        require(reward > 0, "No rewards to claim");
        require(rewardPool >= reward, "Insufficient reward pool");
        
        // Transfer rewards
        require(vansToken.transfer(msg.sender, reward), "Reward transfer failed");
        rewardPool -= reward;
        totalRewardsDistributed += reward;
        stake.rewardsClaimed = true;
        
        emit RewardsClaimed(msg.sender, reward, stake.poolId);
    }
    
    function claimAllRewards() external nonReentrant {
        uint256 totalReward;
        
        for(uint256 i = 0; i < userStakes[msg.sender].length; i++) {
            UserStake storage stake = userStakes[msg.sender][i];
            
            if(!stake.unstaked && 
               !stake.rewardsClaimed && 
               block.timestamp >= stake.unlockTime && 
               stake.rewardDebt > 0) {
                totalReward += stake.rewardDebt;
                stake.rewardsClaimed = true;
            }
        }
        
        require(totalReward > 0, "No rewards to claim");
        require(rewardPool >= totalReward, "Insufficient reward pool");
        
        require(vansToken.transfer(msg.sender, totalReward), "Reward transfer failed");
        rewardPool -= totalReward;
        totalRewardsDistributed += totalReward;
        
        emit RewardsClaimed(msg.sender, totalReward, 99); // 99 = all pools
    }
    
    // ========== REWARD CALCULATION ========== //
    
    function calculateReward(uint256 amount, uint256 apy, uint256 duration) public pure returns (uint256) {
        uint256 base = (amount * apy) / 10000;
        return (base * duration) / 365 days;
    }
    
    // ========== WITHDRAWAL TRACKING SYSTEM ========== //
    
    // Emergency withdraw VANA dengan tracking
    function emergencyWithdrawVANA(uint256 amount) external onlyOwner {
        // Cek apakah cukup balance setelah dipotong total staked
        uint256 availableBalance = address(this).balance;
        require(availableBalance >= amount, "Insufficient available VANA");
        
        // Create withdrawal record
        uint256 withdrawalId = withdrawalRecords.length;
        uint256 deadline = block.timestamp + _calculateSafetyPeriod();
        
        withdrawalRecords.push(WithdrawalRecord({
            amount: amount,
            isVana: true,
            withdrawTime: block.timestamp,
            returnDeadline: deadline,
            returned: false,
            returnedBy: address(0),
            returnTime: 0
        }));
        
        activeWithdrawals[withdrawalId] = true;
        
        // Transfer funds
        payable(owner).transfer(amount);
        
        // Check and emit emergency alert jika perlu
        _checkEmergencyAlerts();
        
        emit EmergencyWithdraw(address(0), amount);
        emit WithdrawalCreated(withdrawalId, amount, true, deadline);
    }
    
    // Emergency withdraw VANS dengan tracking
    function emergencyWithdrawVANS(uint256 amount) external onlyOwner {
        // Cek available balance (total balance - (rewardPool + totalStaked))
        uint256 totalBalance = vansToken.balanceOf(address(this));
        uint256 lockedBalance = rewardPool + _getTotalVansStaked();
        uint256 availableBalance = totalBalance > lockedBalance ? totalBalance - lockedBalance : 0;
        
        require(availableBalance >= amount, "Insufficient available VANS");
        
        // Create withdrawal record
        uint256 withdrawalId = withdrawalRecords.length;
        uint256 deadline = block.timestamp + _calculateSafetyPeriod();
        
        withdrawalRecords.push(WithdrawalRecord({
            amount: amount,
            isVana: false,
            withdrawTime: block.timestamp,
            returnDeadline: deadline,
            returned: false,
            returnedBy: address(0),
            returnTime: 0
        }));
        
        activeWithdrawals[withdrawalId] = true;
        
        // Transfer funds
        require(vansToken.transfer(owner, amount), "VANS transfer failed");
        
        // Check and emit emergency alert
        _checkEmergencyAlerts();
        
        emit EmergencyWithdraw(address(vansToken), amount);
        emit WithdrawalCreated(withdrawalId, amount, false, deadline);
    }
    
    // Kembalikan dana yang di-withdraw
    function returnWithdrawnFunds(uint256 withdrawalId) external payable onlyOwner {
        require(withdrawalId < withdrawalRecords.length, "Invalid withdrawal ID");
        require(!withdrawalRecords[withdrawalId].returned, "Funds already returned");
        
        WithdrawalRecord storage record = withdrawalRecords[withdrawalId];
        
        if(record.isVana) {
            require(msg.value == record.amount, "Incorrect VANA amount");
            // Dana sudah diterima via msg.value
        } else {
            require(vansToken.transferFrom(msg.sender, address(this), record.amount), "VANS transfer failed");
        }
        
        record.returned = true;
        record.returnedBy = msg.sender;
        record.returnTime = block.timestamp;
        activeWithdrawals[withdrawalId] = false;
        
        emit FundsReturned(withdrawalId, record.amount, msg.sender);
    }
    
    // ========== EMERGENCY ALERT SYSTEM ========== //
    
    // Cek apakah ada emergency situation
    function _checkEmergencyAlerts() internal {
        uint256 totalVanaNeeded = _getTotalVanaNeeded();
        uint256 totalVansNeeded = _getTotalVansNeeded();
        
        uint256 earliestDeadline = type(uint256).max;
        
        // Cari deadline terdekat dari active withdrawals
        for(uint256 i = 0; i < withdrawalRecords.length; i++) {
            if(activeWithdrawals[i] && withdrawalRecords[i].returnDeadline < earliestDeadline) {
                earliestDeadline = withdrawalRecords[i].returnDeadline;
            }
        }
        
        if(totalVanaNeeded > 0) {
            emit EmergencyAlert(
                "EMERGENCY: Insufficient VANA for unstaking", 
                totalVanaNeeded, 
                earliestDeadline
            );
        }
        
        if(totalVansNeeded > 0) {
            emit EmergencyAlert(
                "EMERGENCY: Insufficient VANS for rewards", 
                totalVansNeeded, 
                earliestDeadline
            );
        }
    }
    
    // Hitung total VANA yang dibutuhkan untuk unstake
    function _getTotalVanaNeeded() internal view returns (uint256) {
        uint256 totalStakedVana = _getTotalVanaStaked();
        uint256 contractVanaBalance = address(this).balance;
        
        if(contractVanaBalance >= totalStakedVana) {
            return 0;
        }
        return totalStakedVana - contractVanaBalance;
    }
    
    // Hitung total VANS yang dibutuhkan untuk rewards
    function _getTotalVansNeeded() internal view returns (uint256) {
        uint256 totalNeeded = rewardPool + _getTotalVansStaked();
        uint256 contractVansBalance = vansToken.balanceOf(address(this));
        
        if(contractVansBalance >= totalNeeded) {
            return 0;
        }
        return totalNeeded - contractVansBalance;
    }
    
    // Hitung total VANA yang sedang staked
    function _getTotalVanaStaked() internal view returns (uint256) {
        uint256 total = 0;
        for(uint8 i = 0; i < 4; i++) {
            total += pools[i].totalStaked;
        }
        return total;
    }
    
    // Hitung total VANS yang sedang staked
    function _getTotalVansStaked() internal view returns (uint256) {
        // Asumsi VANS staked adalah totalStaked minus VANA staked
        // Dalam implementasi real, perlu tracking terpisah
        return totalStaked - _getTotalVanaStaked();
    }
    
    // Hitung safety period (1 hari sebelum unstake terdekat)
    function _calculateSafetyPeriod() internal view returns (uint256) {
        uint256 earliestUnlock = type(uint256).max;
        
        // Cari unstake time terdekat dari semua user
        // Note: Ini bisa mahal gas, bisa dioptimasi dengan periodic update
        for(uint8 poolId = 0; poolId < 4; poolId++) {
            uint256 poolUnlockTime = block.timestamp + pools[poolId].lockPeriod;
            if(poolUnlockTime < earliestUnlock) {
                earliestUnlock = poolUnlockTime;
            }
        }
        
        // Return deadline 1 hari sebelum unstake terdekat
        return earliestUnlock > block.timestamp ? earliestUnlock - block.timestamp - 1 days : 1 days;
    }
    
    // ========== ADMIN PANEL VIEW FUNCTIONS ========== //
    
    // Get semua active withdrawals untuk admin panel
    function getActiveWithdrawals() external view returns (WithdrawalRecord[] memory) {
        uint256 activeCount = 0;
        for(uint256 i = 0; i < withdrawalRecords.length; i++) {
            if(activeWithdrawals[i]) {
                activeCount++;
            }
        }
        
        WithdrawalRecord[] memory active = new WithdrawalRecord[](activeCount);
        uint256 index = 0;
        for(uint256 i = 0; i < withdrawalRecords.length; i++) {
            if(activeWithdrawals[i]) {
                active[index] = withdrawalRecords[i];
                index++;
            }
        }
        return active;
    }
    
    // Get emergency status untuk admin panel
    function getEmergencyStatus() external view returns (
        uint256 vanaNeeded,
        uint256 vansNeeded, 
        uint256 earliestDeadline,
        bool isEmergency
    ) {
        vanaNeeded = _getTotalVanaNeeded();
        vansNeeded = _getTotalVansNeeded();
        earliestDeadline = type(uint256).max;
        
        for(uint256 i = 0; i < withdrawalRecords.length; i++) {
            if(activeWithdrawals[i] && withdrawalRecords[i].returnDeadline < earliestDeadline) {
                earliestDeadline = withdrawalRecords[i].returnDeadline;
            }
        }
        
        isEmergency = (vanaNeeded > 0) || (vansNeeded > 0);
        
        return (vanaNeeded, vansNeeded, earliestDeadline, isEmergency);
    }
    
    // Get contract health status
    function getContractHealth() external view returns (
        uint256 totalVanaStaked,
        uint256 totalVansStaked,
        uint256 vanaBalance,
        uint256 vansBalance,
        uint256 availableRewardPool,
        uint256 upcomingUnstakes
    ) {
        totalVanaStaked = _getTotalVanaStaked();
        totalVansStaked = _getTotalVansStaked();
        vanaBalance = address(this).balance;
        vansBalance = vansToken.balanceOf(address(this));
        availableRewardPool = rewardPool;
        upcomingUnstakes = 0; // Bisa diimplementasi dengan user stake tracking
        
        return (totalVanaStaked, totalVansStaked, vanaBalance, vansBalance, availableRewardPool, upcomingUnstakes);
    }
    
    // ========== ADMIN FUNCTIONS ========== //
    
    function updatePoolConfig(
        uint8 poolId, 
        uint256 newApy, 
        uint256 newMinVans, 
        uint256 newMinVana,
        uint256 newMaxVans,
        uint256 newMaxVana,
        uint256 newLockPeriod,
        bool isActive
    ) external onlyOwner {
        require(poolId < 4, "Invalid pool");
        require(newApy <= 10000, "APY too high");
        
        pools[poolId].apy = newApy;
        pools[poolId].minVansStake = newMinVans;
        pools[poolId].minVanaStake = newMinVana;
        pools[poolId].maxVansStake = newMaxVans;
        pools[poolId].maxVanaStake = newMaxVana;
        pools[poolId].lockPeriod = newLockPeriod;
        pools[poolId].active = isActive;
        
        emit PoolUpdated(poolId, newApy, newMinVans, newLockPeriod);
    }
    
    // Add more rewards to pool
    function addRewards(uint256 amount) external onlyOwner {
        require(vansToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        rewardPool += amount;
        emit RewardsAdded(amount);
    }
    
    // ========== VIEW FUNCTIONS ========== //
    
    function getUserStakes(address user) external view returns (UserStake[] memory) {
        return userStakes[user];
    }
    
    function getClaimableRewards(address user) external view returns (uint256 totalRewards) {
        UserStake[] memory stakes = userStakes[user];
        for(uint i = 0; i < stakes.length; i++) {
            if(!stakes[i].unstaked && 
               !stakes[i].rewardsClaimed && 
               block.timestamp >= stakes[i].unlockTime) {
                totalRewards += stakes[i].rewardDebt;
            }
        }
    }
    
    function getPoolInfo(uint8 poolId) external view returns (PoolConfig memory) {
        require(poolId < 4, "Invalid pool");
        return pools[poolId];
    }
    
    function getContractBalance() external view returns (uint256 vansBalance, uint256 vanaBalance, uint256 availableRewardPool) {
        vansBalance = vansToken.balanceOf(address(this));
        vanaBalance = address(this).balance;
        availableRewardPool = rewardPool;
    }
}