// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract VanaBatchTransfer {
    address public owner;
    address public feeReceiver;
    uint256 public feeAmount = 0;
    bool public feeEnabled = false;
    
    uint256 public totalFeesCollected;
    uint256 public totalBatchesProcessed;
    uint256 public totalTokensTransferred;
    
    event BatchTransferExecuted(
        address indexed sender,
        address indexed token,
        uint256 recipientCount,
        uint256 totalAmount,
        uint256 feePaid,
        uint256 timestamp
    );
    
    event FeeUpdated(uint256 newFeeAmount);
    event FeeReceiverUpdated(address newReceiver);
    event FeeToggled(bool enabled);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event FeesWithdrawn(uint256 amount);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier validArrayLength(uint256 recipientsLength, uint256 amountsLength) {
        require(recipientsLength == amountsLength, "Arrays length mismatch");
        require(recipientsLength > 0, "No recipients provided");
        require(recipientsLength <= 100, "Max 100 recipients per batch"); // Reduced from 200
        _;
    }
    
    constructor() {
        owner = msg.sender;
        feeReceiver = msg.sender;
    }
    
    // Main batch transfer function - FIXED REENTRANCY
    function batchTransfer(
        address tokenAddress,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external payable validArrayLength(recipients.length, amounts.length) returns (bool) {
        
        // Handle fee collection
        uint256 feePaid = _collectFee();
        
        IERC20 token = IERC20(tokenAddress);
        uint256 totalAmount = 0;
        
        // Calculate total amount needed
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient address");
            require(recipients[i] != address(this), "Cannot transfer to contract itself");
            require(amounts[i] > 0, "Amount must be greater than 0");
            totalAmount += amounts[i];
        }
        
        // Check sender's balance
        require(token.balanceOf(msg.sender) >= totalAmount, "Insufficient token balance");
        
        // Check allowance and approve if needed
        uint256 allowance = token.allowance(msg.sender, address(this));
        if (allowance < totalAmount) {
            require(token.approve(address(this), totalAmount), "Approval failed");
        }
        
        // CEI PATTERN: Update state BEFORE external calls
        totalBatchesProcessed++;
        totalTokensTransferred += totalAmount;
        
        // Execute transfers (external calls LAST)
        for (uint256 i = 0; i < recipients.length; i++) {
            bool success = token.transferFrom(msg.sender, recipients[i], amounts[i]);
            require(success, "Transfer failed");
        }
        
        emit BatchTransferExecuted(
            msg.sender,
            tokenAddress,
            recipients.length,
            totalAmount,
            feePaid,
            block.timestamp
        );
        
        return true;
    }
    
    // Batch transfer with automatic decimals detection - FIXED REENTRANCY
    function batchTransferAutoDecimals(
        address tokenAddress,
        address[] calldata recipients,
        uint256[] calldata rawAmounts
    ) external payable validArrayLength(recipients.length, rawAmounts.length) returns (bool) {
        
        // Handle fee collection
        uint256 feePaid = _collectFee();
        
        IERC20 token = IERC20(tokenAddress);
        uint8 decimals = _getTokenDecimals(tokenAddress);
        
        uint256 totalAmount = 0;
        uint256[] memory adjustedAmounts = new uint256[](recipients.length);
        
        // Convert raw amounts to token decimals
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient address");
            require(recipients[i] != address(this), "Cannot transfer to contract itself");
            require(rawAmounts[i] > 0, "Amount must be greater than 0");
            
            uint256 adjustedAmount = rawAmounts[i] * (10 ** decimals);
            adjustedAmounts[i] = adjustedAmount;
            totalAmount += adjustedAmount;
        }
        
        // Check sender's balance
        require(token.balanceOf(msg.sender) >= totalAmount, "Insufficient token balance");
        
        // Check allowance and approve if needed
        uint256 allowance = token.allowance(msg.sender, address(this));
        if (allowance < totalAmount) {
            require(token.approve(address(this), totalAmount), "Approval failed");
        }
        
        // CEI PATTERN: Update state BEFORE external calls
        totalBatchesProcessed++;
        totalTokensTransferred += totalAmount;
        
        // Execute transfers (external calls LAST)
        for (uint256 i = 0; i < recipients.length; i++) {
            bool success = token.transferFrom(msg.sender, recipients[i], adjustedAmounts[i]);
            require(success, "Transfer failed");
        }
        
        emit BatchTransferExecuted(
            msg.sender,
            tokenAddress,
            recipients.length,
            totalAmount,
            feePaid,
            block.timestamp
        );
        
        return true;
    }
    
    // Internal function to collect fee
    function _collectFee() internal returns (uint256) {
        if (!feeEnabled) {
            // Refund any sent ETH if fee is disabled
            if (msg.value > 0) {
                (bool refundSuccess, ) = msg.sender.call{value: msg.value}("");
                require(refundSuccess, "Refund failed");
            }
            return 0;
        }
        
        require(msg.value >= feeAmount, "Insufficient fee");
        
        uint256 feeToCollect = feeAmount;
        uint256 refund = msg.value - feeToCollect;
        
        // Collect fee
        if (feeToCollect > 0) {
            (bool success, ) = feeReceiver.call{value: feeToCollect}("");
            require(success, "Fee transfer failed");
            totalFeesCollected += feeToCollect;
        }
        
        // Refund excess
        if (refund > 0) {
            (bool refundSuccess, ) = msg.sender.call{value: refund}("");
            require(refundSuccess, "Refund failed");
        }
        
        return feeToCollect;
    }
    
    // Get token decimals with error handling
    function _getTokenDecimals(address tokenAddress) internal view returns (uint8) {
        try IERC20(tokenAddress).decimals() returns (uint8 decimal) {
            return decimal;
        } catch {
            return 18; // Default to 18 if call fails
        }
    }
    
    // Get estimated fee for batch transfer
    function getEstimatedFee() external view returns (uint256) {
        return feeEnabled ? feeAmount : 0;
    }
    
    // Get token info
    function getTokenInfo(address tokenAddress) external view returns (
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 totalSupply,
        uint256 yourBalance
    ) {
        IERC20 token = IERC20(tokenAddress);
        
        try token.name() returns (string memory tokenName) {
            name = tokenName;
        } catch {
            name = "Unknown";
        }
        
        try token.symbol() returns (string memory tokenSymbol) {
            symbol = tokenSymbol;
        } catch {
            symbol = "UNKNOWN";
        }
        
        try token.decimals() returns (uint8 tokenDecimals) {
            decimals = tokenDecimals;
        } catch {
            decimals = 18;
        }
        
        try token.totalSupply() returns (uint256 supply) {
            totalSupply = supply;
        } catch {
            totalSupply = 0;
        }
        
        yourBalance = token.balanceOf(msg.sender);
    }
    
    // Owner functions
    
    function setFeeAmount(uint256 newFeeAmount) external onlyOwner {
        feeAmount = newFeeAmount;
        emit FeeUpdated(newFeeAmount);
    }
    
    function setFeeReceiver(address newReceiver) external onlyOwner {
        require(newReceiver != address(0), "Invalid receiver address");
        require(newReceiver != address(this), "Cannot set contract as fee receiver");
        feeReceiver = newReceiver;
        emit FeeReceiverUpdated(newReceiver);
    }
    
    function toggleFee(bool enable) external onlyOwner {
        feeEnabled = enable;
        emit FeeToggled(enable);
    }
    
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid new owner");
        require(newOwner != address(this), "Cannot transfer to contract itself");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
    
    // Withdraw collected fees (native token) - hanya untuk owner
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        
        require(balance > 0, "No fees to withdraw");
        
        (bool success, ) = feeReceiver.call{value: balance}("");
        require(success, "Fee withdrawal failed");
        
        emit FeesWithdrawn(balance);
    }
    
    // Get contract statistics
    function getStats() external view returns (
        uint256 batches,
        uint256 totalTokens,
        uint256 totalFees,
        uint256 contractBalance
    ) {
        return (
            totalBatchesProcessed,
            totalTokensTransferred,
            totalFeesCollected,
            address(this).balance
        );
    }
    
    // Check if contract can handle token (view function for UI)
    function canHandleToken(address tokenAddress) external view returns (bool) {
        try IERC20(tokenAddress).decimals() returns (uint8) {
            return true;
        } catch {
            return false;
        }
    }
    
    // Fallback functions
    receive() external payable {
        // Accept native tokens (for fees)
    }
}