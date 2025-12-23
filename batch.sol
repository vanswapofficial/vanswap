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
        require(msg.sender == owner, "Only owner can call");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        feeReceiver = msg.sender;
    }
    
    // Main batch transfer function
    function batchTransfer(
        address tokenAddress,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external payable returns (bool) {
        uint256 feePaid = _collectFee();
        
        // Validate arrays
        require(recipients.length == amounts.length, "Arrays length mismatch");
        require(recipients.length > 0, "No recipients");
        require(recipients.length <= 100, "Too many recipients");
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient");
            require(amounts[i] > 0, "Amount must be > 0");
            totalAmount += amounts[i];
        }
        
        IERC20 token = IERC20(tokenAddress);
        require(token.balanceOf(msg.sender) >= totalAmount, "Insufficient balance");
        
        uint256 allowance = token.allowance(msg.sender, address(this));
        if (allowance < totalAmount) {
            require(token.approve(address(this), totalAmount), "Approval failed");
        }
        
        // Update stats
        totalBatchesProcessed++;
        totalTokensTransferred += totalAmount;
        
        // Execute transfers
        for (uint256 i = 0; i < recipients.length; i++) {
            require(token.transferFrom(msg.sender, recipients[i], amounts[i]), "Transfer failed");
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
    
    // Batch transfer dengan auto decimals
    function batchTransferAutoDecimals(
        address tokenAddress,
        address[] calldata recipients,
        uint256[] calldata rawAmounts
    ) external payable returns (bool) {
        uint256 feePaid = _collectFee();
        
        // Validate arrays
        require(recipients.length == rawAmounts.length, "Arrays length mismatch");
        require(recipients.length > 0, "No recipients");
        require(recipients.length <= 100, "Too many recipients");
        
        // Get token decimals
        uint8 decimals = _getTokenDecimals(tokenAddress);
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient");
            require(rawAmounts[i] > 0, "Amount must be > 0");
            
            uint256 adjustedAmount = rawAmounts[i] * (10 ** decimals);
            totalAmount += adjustedAmount;
        }
        
        IERC20 token = IERC20(tokenAddress);
        require(token.balanceOf(msg.sender) >= totalAmount, "Insufficient balance");
        
        uint256 allowance = token.allowance(msg.sender, address(this));
        if (allowance < totalAmount) {
            require(token.approve(address(this), totalAmount), "Approval failed");
        }
        
        // Update stats
        totalBatchesProcessed++;
        totalTokensTransferred += totalAmount;
        
        // Execute transfers
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 adjustedAmount = rawAmounts[i] * (10 ** decimals);
            require(token.transferFrom(msg.sender, recipients[i], adjustedAmount), "Transfer failed");
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
    function _collectFee() private returns (uint256) {
        if (!feeEnabled) {
            if (msg.value > 0) {
                (bool refundSuccess, ) = msg.sender.call{value: msg.value}("");
                require(refundSuccess, "Refund failed");
            }
            return 0;
        }
        
        require(msg.value >= feeAmount, "Insufficient fee");
        uint256 refund = msg.value - feeAmount;
        
        if (feeAmount > 0) {
            (bool success, ) = feeReceiver.call{value: feeAmount}("");
            require(success, "Fee transfer failed");
            totalFeesCollected += feeAmount;
        }
        
        if (refund > 0) {
            (bool refundSuccess, ) = msg.sender.call{value: refund}("");
            require(refundSuccess, "Refund failed");
        }
        
        return feeAmount;
    }
    
    // Get token decimals
    function _getTokenDecimals(address tokenAddress) private view returns (uint8) {
        try IERC20(tokenAddress).decimals() returns (uint8 decimal) {
            return decimal;
        } catch {
            return 18;
        }
    }
    
    // Owner functions
    function setFeeAmount(uint256 newFeeAmount) external onlyOwner {
        feeAmount = newFeeAmount;
        emit FeeUpdated(newFeeAmount);
    }
    
    function setFeeReceiver(address newReceiver) external onlyOwner {
        require(newReceiver != address(0), "Invalid receiver");
        feeReceiver = newReceiver;
        emit FeeReceiverUpdated(newReceiver);
    }
    
    function toggleFee(bool enable) external onlyOwner {
        feeEnabled = enable;
        emit FeeToggled(enable);
    }
    
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid new owner");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
    
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        
        (bool success, ) = feeReceiver.call{value: balance}("");
        require(success, "Fee withdrawal failed");
        
        emit FeesWithdrawn(balance);
    }
    
    // View functions
    function getEstimatedFee() external view returns (uint256) {
        return feeEnabled ? feeAmount : 0;
    }
    
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
    
    function getContractInfo() external view returns (
        address _owner,
        address _feeReceiver,
        uint256 _feeAmount,
        bool _feeEnabled,
        uint256 _batchesProcessed,
        uint256 _tokensTransferred,
        uint256 _feesCollected,
        uint256 _contractBalance
    ) {
        return (
            owner,
            feeReceiver,
            feeAmount,
            feeEnabled,
            totalBatchesProcessed,
            totalTokensTransferred,
            totalFeesCollected,
            address(this).balance
        );
    }
    
    // Check if token is compatible
    function canHandleToken(address tokenAddress) external view returns (bool) {
        try IERC20(tokenAddress).decimals() returns (uint8) {
            return true;
        } catch {
            return false;
        }
    }
    
    // Calculate adjusted amount based on token decimals
    function calculateAdjustedAmount(uint256 rawAmount, address tokenAddress) external view returns (uint256) {
        uint8 decimals = _getTokenDecimals(tokenAddress);
        return rawAmount * (10 ** decimals);
    }
    
    // Receive native tokens (for fees)
    receive() external payable {}
    
    // Prevent accidental ERC20 transfers to contract
    function onERC20Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        revert("Direct token transfers not allowed. Use batchTransfer function.");
    }
}