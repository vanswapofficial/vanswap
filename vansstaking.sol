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
    
    // Events
    event Staked(address indexed user, uint256 amount, bool isVana, uint8 poolId, uint256 unlockTime);
    event Unstaked(address indexed user, uint256 amount, uint8 poolId);
    event RewardsClaimed(address indexed user, uint256 amount, uint8 poolId);
    event PoolUpdated(uint8 poolId, uint256 apy, uint256 minStake, uint256 lockPeriod);
    emergencyWithdraw(address token, uint256 amount);
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
        
        // Hitung berapa banyak unstake dalam 7 hari ke depan
        upcomingUnstakes = 0;
        // Implementasi bisa ditambahkan untuk tracking user stakes
    }

    // ... (Fungsi-fungsi lainnya tetap sama: stake, unstake, claim, dll)
}