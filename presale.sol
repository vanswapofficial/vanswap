// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract VANSPresale is ReentrancyGuard, Ownable {
    using SafeMath for uint256;

    // Token information
    IERC20 public vansToken;
    uint256 public constant TOTAL_SUPPLY = 120_000_000 * 10**18; // 120 juta VANS
    uint256 public constant PRESALE_PERCENTAGE = 30; // 30% untuk presale
    uint256 public constant PRESALE_TOKENS = TOTAL_SUPPLY * PRESALE_PERCENTAGE / 100; // 36 juta VANS

    // Presale configuration
    uint256 public constant SOFT_CAP_VANA = 2_000 * 10**18; // 2000 VANA
    uint256 public constant HARD_CAP_VANA = 3_600 * 10**18; // 3600 VANA
    uint256 public constant MIN_CONTRIBUTION = 1 * 10**17; // 0.1 VANA minimum
    uint256 public constant MAX_CONTRIBUTION = 100 * 10**18; // 100 VANA maximum per address
    uint256 public constant PRESALE_DURATION = 90 days; // 3 BULAN

    // Price calculation: 1 VANA = ? VANS
    uint256 public constant TOKENS_PER_VANA = PRESALE_TOKENS / HARD_CAP_VANA; // 10,000 VANS per VANA

    // Presale state
    uint256 public totalRaised;
    uint256 public startTime;
    uint256 public endTime;
    bool public presaleFinalized;
    bool public softCapReached;
    bool public presaleStarted;

    // Vesting configuration
    uint256 public constant CLIFF_DURATION = 2 weeks;
    uint256 public constant VESTING_DURATION = 90 days; // 3 bulan
    uint256 public constant RELEASE_INTERVAL = 7 days; // Claim setiap minggu
    uint256 public constant CLIFF_PERCENTAGE = 20; // 20% release di cliff
    uint256 public constant VESTING_PERCENTAGE = 80; // 80% vesting

    // Participant information
    struct Participant {
        uint256 contributed;
        uint256 tokensBought;
        uint256 tokensClaimed;
        uint256 lastClaimTime;
        bool refunded;
    }

    mapping(address => Participant) public participants;
    address[] public participantAddresses;

    // Events
    event PresaleStarted(uint256 startTime, uint256 endTime);
    event TokensPurchased(address indexed buyer, uint256 vanaAmount, uint256 tokenAmount);
    event TokensClaimed(address indexed claimer, uint256 amount);
    event RefundClaimed(address indexed refundee, uint256 amount);
    event PresaleFinalized(bool success, uint256 totalRaised);
    event FundsWithdrawn(address indexed owner, uint256 amount);

    constructor(address _vansToken) {
        require(_vansToken != address(0), "Invalid token address");
        vansToken = IERC20(_vansToken);
    }

    // Modifiers
    modifier presaleActive() {
        require(presaleStarted, "Presale not started");
        require(block.timestamp >= startTime, "Presale not started yet");
        require(block.timestamp <= endTime, "Presale ended");
        require(!presaleFinalized, "Presale finalized");
        _;
    }

    modifier presaleEnded() {
        require(presaleStarted, "Presale not started");
        require(block.timestamp > endTime || presaleFinalized, "Presale not ended");
        _;
    }

    modifier onlyParticipant() {
        require(participants[msg.sender].contributed > 0, "Not a participant");
        _;
    }

    // Start presale function - only owner
    function startPresale() external onlyOwner {
        require(!presaleStarted, "Presale already started");
        
        // Check if contract has enough VANS tokens
        uint256 ownerBalance = vansToken.balanceOf(owner());
        require(ownerBalance >= PRESALE_TOKENS, "Owner doesn't have enough VANS tokens");
        
        presaleStarted = true;
        startTime = block.timestamp;
        endTime = block.timestamp + PRESALE_DURATION;

        emit PresaleStarted(startTime, endTime);
    }

    // Buy tokens with VANA
    function buyTokens() external payable presaleActive nonReentrant {
        require(msg.value >= MIN_CONTRIBUTION, "Contribution too low");
        require(msg.value <= MAX_CONTRIBUTION, "Contribution too high");
        require(totalRaised + msg.value <= HARD_CAP_VANA, "Hard cap reached");

        Participant storage participant = participants[msg.sender];
        
        // Check total contribution per address
        uint256 newContribution = participant.contributed + msg.value;
        require(newContribution <= MAX_CONTRIBUTION, "Max contribution per address exceeded");

        // Calculate tokens to allocate
        uint256 tokensToAllocate = calculateTokens(msg.value);
        require(tokensToAllocate > 0, "Token calculation error");

        // First time contributor
        if (participant.contributed == 0) {
            participantAddresses.push(msg.sender);
        }

        // Update participant info
        participant.contributed = newContribution;
        participant.tokensBought += tokensToAllocate;

        // Update total raised
        totalRaised += msg.value;

        // Check if soft cap is reached
        if (!softCapReached && totalRaised >= SOFT_CAP_VANA) {
            softCapReached = true;
        }

        emit TokensPurchased(msg.sender, msg.value, tokensToAllocate);
    }

    // Calculate tokens based on VANA amount
    function calculateTokens(uint256 vanaAmount) public pure returns (uint256) {
        return vanaAmount * TOKENS_PER_VANA;
    }

    // Claim tokens after presale
    function claimTokens() external presaleEnded nonReentrant onlyParticipant {
        require(presaleFinalized, "Presale not finalized");
        require(softCapReached, "Soft cap not reached - use refund instead");
        
        Participant storage participant = participants[msg.sender];
        require(!participant.refunded, "Already refunded");
        require(participant.tokensBought > 0, "No tokens to claim");
        require(participant.tokensClaimed < participant.tokensBought, "All tokens already claimed");

        uint256 claimableTokens = getClaimableTokens(msg.sender);
        require(claimableTokens > 0, "No tokens claimable at this time");

        // Check contract token balance
        uint256 contractBalance = vansToken.balanceOf(address(this));
        require(contractBalance >= claimableTokens, "Insufficient tokens in contract");

        participant.tokensClaimed += claimableTokens;
        participant.lastClaimTime = block.timestamp;

        bool success = vansToken.transfer(msg.sender, claimableTokens);
        require(success, "Token transfer failed");

        emit TokensClaimed(msg.sender, claimableTokens);
    }

    // Claim refund if soft cap not reached
    function claimRefund() external presaleEnded nonReentrant onlyParticipant {
        require(presaleFinalized, "Presale not finalized");
        require(!softCapReached, "Soft cap reached - claim tokens instead");
        
        Participant storage participant = participants[msg.sender];
        require(!participant.refunded, "Already refunded");
        require(participant.contributed > 0, "No contribution to refund");

        uint256 refundAmount = participant.contributed;
        participant.refunded = true;

        // Check contract balance
        require(address(this).balance >= refundAmount, "Insufficient contract balance");

        (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
        require(success, "Refund transfer failed");

        emit RefundClaimed(msg.sender, refundAmount);
    }

    // Finalize presale - only owner
    function finalizePresale() external onlyOwner presaleEnded {
        require(!presaleFinalized, "Presale already finalized");

        presaleFinalized = true;

        if (softCapReached) {
            // Transfer raised funds to owner
            uint256 raisedAmount = address(this).balance;
            if (raisedAmount > 0) {
                (bool success, ) = payable(owner()).call{value: raisedAmount}("");
                require(success, "Funds transfer failed");
            }

            // Transfer VANS tokens to contract for distribution
            uint256 tokensToTransfer = PRESALE_TOKENS;
            bool tokenSuccess = vansToken.transferFrom(owner(), address(this), tokensToTransfer);
            require(tokenSuccess, "Token transfer to contract failed");
        }

        emit PresaleFinalized(softCapReached, totalRaised);
    }

    // Add VANS tokens to contract manually (if needed)
    function addTokensToContract(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        bool success = vansToken.transferFrom(owner(), address(this), amount);
        require(success, "Token transfer failed");
    }

    // Emergency withdraw if something goes wrong - only owner
    function emergencyWithdraw() external onlyOwner {
        require(block.timestamp > endTime + 30 days, "Can only emergency withdraw 30 days after presale");
        require(!presaleFinalized, "Presale already finalized");

        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = payable(owner()).call{value: balance}("");
            require(success, "Emergency withdraw failed");
        }

        // Return any VANS tokens to owner
        uint256 tokenBalance = vansToken.balanceOf(address(this));
        if (tokenBalance > 0) {
            vansToken.transfer(owner(), tokenBalance);
        }
    }

    // Calculate claimable tokens for an address
    function getClaimableTokens(address _participant) public view returns (uint256) {
        Participant memory participant = participants[_participant];
        
        if (participant.tokensBought == 0 || participant.refunded) {
            return 0;
        }

        if (!presaleFinalized || !softCapReached) {
            return 0;
        }

        uint256 cliffEndTime = endTime + CLIFF_DURATION;
        
        // Before cliff ends, no tokens claimable
        if (block.timestamp < cliffEndTime) {
            return 0;
        }

        // Calculate total claimable amount
        uint256 totalClaimable = calculateTotalClaimable(participant);
        uint256 alreadyClaimed = participant.tokensClaimed;
        
        if (totalClaimable <= alreadyClaimed) {
            return 0;
        }

        return totalClaimable - alreadyClaimed;
    }

    // Calculate total claimable tokens (cliff + vesting)
    function calculateTotalClaimable(Participant memory participant) internal view returns (uint256) {
        uint256 cliffEndTime = endTime + CLIFF_DURATION;
        uint256 vestingEndTime = cliffEndTime + VESTING_DURATION;

        // Before cliff, no tokens
        if (block.timestamp < cliffEndTime) {
            return 0;
        }

        // Calculate cliff tokens (20%)
        uint256 cliffTokens = participant.tokensBought * CLIFF_PERCENTAGE / 100;

        // After vesting period, all tokens are claimable
        if (block.timestamp >= vestingEndTime) {
            return participant.tokensBought;
        }

        // During vesting period
        uint256 timeInVesting = block.timestamp - cliffEndTime;
        uint256 totalVestingIntervals = VESTING_DURATION / RELEASE_INTERVAL;
        uint256 intervalsPassed = timeInVesting / RELEASE_INTERVAL;
        
        uint256 vestingTokensPerInterval = (participant.tokensBought * VESTING_PERCENTAGE / 100) / totalVestingIntervals;
        uint256 vestingTokensClaimable = intervalsPassed * vestingTokensPerInterval;

        return cliffTokens + vestingTokensClaimable;
    }

    // Get participant count
    function getParticipantCount() external view returns (uint256) {
        return participantAddresses.length;
    }

    // Get contract VANA balance
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // Get contract VANS token balance
    function getTokenBalance() external view returns (uint256) {
        return vansToken.balanceOf(address(this));
    }

    // Get participant info
    function getParticipantInfo(address _participant) external view returns (
        uint256 contributed,
        uint256 tokensBought,
        uint256 tokensClaimed,
        uint256 lastClaimTime,
        bool refunded,
        uint256 claimableTokens
    ) {
        Participant memory p = participants[_participant];
        contributed = p.contributed;
        tokensBought = p.tokensBought;
        tokensClaimed = p.tokensClaimed;
        lastClaimTime = p.lastClaimTime;
        refunded = p.refunded;
        claimableTokens = getClaimableTokens(_participant);
    }

    // Get presale status
    function getPresaleStatus() external view returns (
        uint256 _totalRaised,
        uint256 _participants,
        bool _isActive,
        bool _isFinalized,
        bool _softCapReached,
        bool _isStarted,
        uint256 _timeRemaining,
        uint256 _contractTokenBalance
    ) {
        _totalRaised = totalRaised;
        _participants = participantAddresses.length;
        _isStarted = presaleStarted;
        _isActive = (presaleStarted && block.timestamp >= startTime && block.timestamp <= endTime && !presaleFinalized);
        _isFinalized = presaleFinalized;
        _softCapReached = softCapReached;
        _timeRemaining = presaleStarted && block.timestamp < endTime ? endTime - block.timestamp : 0;
        _contractTokenBalance = vansToken.balanceOf(address(this));
    }

    // Receive function - prevent direct transfers
    receive() external payable {
        revert("Please use buyTokens() function");
    }

    // Fallback function
    fallback() external payable {
        revert("Please use buyTokens() function");
    }
}