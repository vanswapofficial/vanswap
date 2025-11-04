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
    uint256 public constant TOKENS_PER_VANA = PRESALE_TOKENS / HARD_CAP_VANA; // ~10,000 VANS per VANA

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
        vansToken = IERC20(_vansToken);
    }

    // Modifiers
    modifier presaleActive() {
        require(presaleStarted, "Presale not started");
        require(block.timestamp >= startTime && block.timestamp <= endTime, "Presale not active");
        require(!presaleFinalized, "Presale already finalized");
        _;
    }

    modifier presaleEnded() {
        require(presaleStarted && (block.timestamp > endTime || presaleFinalized), "Presale not ended");
        _;
    }

    // Start presale function - only owner
    function startPresale() external onlyOwner {
        require(!presaleStarted, "Presale already started");
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
        
        // Check if address is contributing for the first time
        if (participant.contributed == 0) {
            participantAddresses.push(msg.sender);
        }

        // Update participant info
        participant.contributed += msg.value;
        require(participant.contributed <= MAX_CONTRIBUTION, "Max contribution per address exceeded");

        // Calculate tokens to allocate
        uint256 tokensToAllocate = msg.value * TOKENS_PER_VANA;
        participant.tokensBought += tokensToAllocate;

        // Update total raised
        totalRaised += msg.value;

        // Check if soft cap is reached
        if (!softCapReached && totalRaised >= SOFT_CAP_VANA) {
            softCapReached = true;
        }

        emit TokensPurchased(msg.sender, msg.value, tokensToAllocate);
    }

    // Claim tokens after presale
    function claimTokens() external presaleEnded nonReentrant {
        require(presaleFinalized, "Presale not finalized");
        require(softCapReached, "Soft cap not reached - use refund instead");
        require(!participants[msg.sender].refunded, "Already refunded");

        Participant storage participant = participants[msg.sender];
        require(participant.tokensBought > 0, "No tokens to claim");
        require(participant.tokensClaimed < participant.tokensBought, "All tokens already claimed");

        uint256 claimableTokens = getClaimableTokens(msg.sender);
        require(claimableTokens > 0, "No tokens claimable at this time");

        participant.tokensClaimed += claimableTokens;
        participant.lastClaimTime = block.timestamp;

        require(vansToken.transfer(msg.sender, claimableTokens), "Token transfer failed");

        emit TokensClaimed(msg.sender, claimableTokens);
    }

    // Claim refund if soft cap not reached
    function claimRefund() external presaleEnded nonReentrant {
        require(presaleFinalized, "Presale not finalized");
        require(!softCapReached, "Soft cap reached - claim tokens instead");
        require(!participants[msg.sender].refunded, "Already refunded");

        Participant storage participant = participants[msg.sender];
        require(participant.contributed > 0, "No contribution to refund");

        uint256 refundAmount = participant.contributed;
        participant.refunded = true;

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
            (bool success, ) = payable(owner()).call{value: raisedAmount}("");
            require(success, "Funds transfer failed");

            // Transfer VANS tokens to contract for distribution
            require(vansToken.transferFrom(owner(), address(this), PRESALE_TOKENS), "Token transfer failed");
        }

        emit PresaleFinalized(softCapReached, totalRaised);
    }

    // Emergency withdraw if something goes wrong - only owner
    function emergencyWithdraw() external onlyOwner {
        require(block.timestamp > endTime + 30 days, "Can only emergency withdraw 30 days after presale");
        require(!presaleFinalized, "Presale already finalized");

        uint256 balance = address(this).balance;
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Emergency withdraw failed");

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

        // Calculate cliff release (20%)
        uint256 cliffTokens = participant.tokensBought * CLIFF_PERCENTAGE / 100;
        
        // If never claimed before, start with cliff tokens
        if (participant.lastClaimTime == 0) {
            uint256 vestingTokens = calculateVestingTokens(_participant, cliffEndTime);
            return cliffTokens + vestingTokens;
        }

        // Calculate vesting tokens since last claim
        return calculateVestingTokens(_participant, participant.lastClaimTime);
    }

    // Calculate vesting tokens
    function calculateVestingTokens(address _participant, uint256 _fromTime) internal view returns (uint256) {
        Participant memory participant = participants[_participant];
        uint256 vestingStartTime = endTime + CLIFF_DURATION;
        uint256 vestingEndTime = vestingStartTime + VESTING_DURATION;

        if (_fromTime < vestingStartTime) {
            _fromTime = vestingStartTime;
        }

        if (block.timestamp <= _fromTime) {
            return 0;
        }

        if (block.timestamp >= vestingEndTime) {
            // Return all remaining vesting tokens
            uint256 totalVestingTokens = participant.tokensBought * VESTING_PERCENTAGE / 100;
            return totalVestingTokens - (participant.tokensClaimed - (participant.tokensBought * CLIFF_PERCENTAGE / 100));
        }

        // Calculate based on time passed
        uint256 timePassed = block.timestamp - _fromTime;
        uint256 totalIntervals = VESTING_DURATION / RELEASE_INTERVAL;
        uint256 intervalsPassed = timePassed / RELEASE_INTERVAL;
        
        if (intervalsPassed == 0) {
            return 0;
        }

        uint256 tokensPerInterval = (participant.tokensBought * VESTING_PERCENTAGE / 100) / totalIntervals;
        return intervalsPassed * tokensPerInterval;
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

    // Get presale status
    function getPresaleStatus() external view returns (
        uint256 _totalRaised,
        uint256 _participants,
        bool _isActive,
        bool _isFinalized,
        bool _softCapReached,
        bool _isStarted,
        uint256 _timeRemaining
    ) {
        _totalRaised = totalRaised;
        _participants = participantAddresses.length;
        _isStarted = presaleStarted;
        _isActive = (presaleStarted && block.timestamp >= startTime && block.timestamp <= endTime && !presaleFinalized);
        _isFinalized = presaleFinalized;
        _softCapReached = softCapReached;
        _timeRemaining = presaleStarted && block.timestamp < endTime ? endTime - block.timestamp : 0;
    }

    // Receive function to accept VANA
    receive() external payable {
        buyTokens();
    }
}