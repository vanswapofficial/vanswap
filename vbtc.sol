// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title vBTC - Vana Bitcoin
 */
contract vBTC is ERC20, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    
    // Constants
    uint256 public constant MAX_SUPPLY = 20 * 10**8 * 10**18; // 20 BTC dengan 18 decimals
    uint8 public constant BTC_DECIMALS = 8;
    uint256 public constant SATOSHI_TO_WEI = 10**10; // 1 BTC (10^8 satoshi) = 10^18 wei
    
    // Minting control
    bool public mintingEnabled = true;
    uint256 public totalMinted = 0;
    
    // Events
    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);
    event ReceivedETH(address indexed from, uint256 amount);
    event ReceivedERC20(address indexed token, address indexed from, uint256 amount);
    event MintingStatusChanged(bool enabled);
    
    /**
     * @dev Constructor untuk inisialisasi token vBTC
     * @param initialOwner Alamat pemilik kontrak
     */
    constructor(address initialOwner) 
        ERC20("Vanadium Bitcoin", "vBTC") 
        Ownable(initialOwner)
    {
        // Tidak ada mint awal
    }
    
    /**
     * @dev Fungsi untuk mint token vBTC (hanya owner)
     * @param to Alamat penerima
     * @param amount Jumlah token dalam satoshi (1 BTC = 10^8 satoshi)
     */
    function mint(address to, uint256 amount) external onlyOwner nonReentrant {
        require(mintingEnabled, "Minting is disabled");
        require(to != address(0), "Cannot mint to zero address");
        require(amount > 0, "Amount must be greater than 0");
        
        // Convert from satoshi to token decimals (18) dengan SafeMath
        uint256 mintAmount = amount.mul(SATOSHI_TO_WEI);
        
        // Periksa tidak overflow dan tidak melebihi MAX_SUPPLY
        uint256 newTotal = totalMinted.add(mintAmount);
        require(newTotal <= MAX_SUPPLY, "Exceeds maximum supply");
        
        totalMinted = newTotal;
        _mint(to, mintAmount);
        
        emit Minted(to, mintAmount);
    }
    
    /**
     * @dev Fungsi untuk disable/enable minting (hanya owner)
     * @param enabled Status minting
     */
    function setMintingEnabled(bool enabled) external onlyOwner {
        mintingEnabled = enabled;
        emit MintingStatusChanged(enabled);
    }
    
    /**
     * @dev Fungsi untuk burn token vBTC
     * @param amount Jumlah token dalam satoshi
     */
    function burn(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        
        // Convert from satoshi to token decimals dengan SafeMath
        uint256 burnAmount = amount.mul(SATOSHI_TO_WEI);
        
        // Periksa balance cukup dengan konversi yang benar
        uint256 userBalance = balanceOf(msg.sender);
        require(userBalance >= burnAmount, "Insufficient balance");
        
        _burn(msg.sender, burnAmount);
        
        emit Burned(msg.sender, burnAmount);
    }
    
    /**
     * @dev Konversi dari satoshi ke vBTC token amount
     * @param satoshi Jumlah dalam satoshi
     * @return Jumlah token vBTC
     */
    function satoshiToToken(uint256 satoshi) public pure returns (uint256) {
        return satoshi.mul(SATOSHI_TO_WEI);
    }
    
    /**
     * @dev Konversi dari vBTC token amount ke satoshi
     * @param tokenAmount Jumlah token vBTC
     * @return Jumlah dalam satoshi
     */
    function tokenToSatoshi(uint256 tokenAmount) public pure returns (uint256) {
        require(tokenAmount % SATOSHI_TO_WEI == 0, "Token amount must be whole satoshis");
        return tokenAmount.div(SATOSHI_TO_WEI);
    }
    
    /**
     * @dev Mendapatkan total supply dalam satoshi
     * @return Total supply dalam satoshi
     */
    function totalSupplyInSatoshi() public view returns (uint256) {
        return totalSupply().div(SATOSHI_TO_WEI);
    }
    
    /**
     * @dev Mendapatkan balance dalam satoshi
     * @param account Alamat pemilik
     * @return Balance dalam satoshi
     */
    function balanceOfInSatoshi(address account) public view returns (uint256) {
        return balanceOf(account).div(SATOSHI_TO_WEI);
    }
    
    /**
     * @dev Mendapatkan balance tepat dalam satoshi (dengan rounding down)
     * @param account Alamat pemilik
     * @return Balance dalam satoshi
     */
    function balanceOfInExactSatoshi(address account) public view returns (uint256) {
        uint256 balance = balanceOf(account);
        require(balance % SATOSHI_TO_WEI == 0, "Balance contains fractional satoshi");
        return balance.div(SATOSHI_TO_WEI);
    }
    
    /**
     * @dev Menerima ETH (native) tanpa fee
     */
    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
        // ETH diterima tanpa kondisi khusus
    }
    
    /**
     * @dev Fallback function
     */
    fallback() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }
    
    /**
     * @dev Fungsi untuk menarik ETH yang terkumpul di kontrak (hanya owner)
     * @param amount Jumlah ETH yang akan ditarik
     */
    function withdrawETH(uint256 amount) external onlyOwner nonReentrant {
        require(address(this).balance >= amount, "Insufficient ETH balance");
        payable(owner()).transfer(amount);
    }
    
    /**
     * @dev Fungsi untuk menarik semua ETH yang terkumpul di kontrak (hanya owner)
     */
    function withdrawAllETH() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH balance");
        payable(owner()).transfer(balance);
    }
    
    /**
     * @dev Fungsi untuk menarik token ERC20 yang tidak sengaja dikirim ke kontrak (hanya owner)
     * @param tokenAddress Alamat token ERC20
     * @param amount Jumlah token yang akan ditarik
     */
    function withdrawERC20(address tokenAddress, uint256 amount) external onlyOwner nonReentrant {
        require(tokenAddress != address(this), "Cannot withdraw vBTC tokens");
        require(tokenAddress != address(0), "Invalid token address");
        
        IERC20 token = IERC20(tokenAddress);
        uint256 tokenBalance = token.balanceOf(address(this));
        require(tokenBalance >= amount, "Insufficient token balance");
        
        bool success = token.transfer(owner(), amount);
        require(success, "Token transfer failed");
    }
    
    /**
     * @dev Transfer token vBTC (override untuk nonReentrant)
     */
    function transfer(address to, uint256 amount) public override nonReentrant returns (bool) {
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Amount must be greater than 0");
        return super.transfer(to, amount);
    }
    
    /**
     * @dev Transfer dari alamat lain (override untuk nonReentrant)
     */
    function transferFrom(address from, address to, uint256 amount) public override nonReentrant returns (bool) {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Amount must be greater than 0");
        return super.transferFrom(from, to, amount);
    }
    
    /**
     * @dev Approve spending (override untuk nonReentrant)
     */
    function approve(address spender, uint256 amount) public override nonReentrant returns (bool) {
        require(spender != address(0), "ERC20: approve to the zero address");
        return super.approve(spender, amount);
    }
    
    /**
     * @dev Increase allowance (override untuk nonReentrant)
     */
    function increaseAllowance(address spender, uint256 addedValue) public override nonReentrant returns (bool) {
        require(spender != address(0), "ERC20: approve to the zero address");
        return super.increaseAllowance(spender, addedValue);
    }
    
    /**
     * @dev Decrease allowance (override untuk nonReentrant)
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public override nonReentrant returns (bool) {
        require(spender != address(0), "ERC20: approve to the zero address");
        return super.decreaseAllowance(spender, subtractedValue);
    }
    
    /**
     * @dev Emergency function untuk recover token vBTC yang stuck (hanya owner)
     * Hanya untuk kasus token terkirim ke kontrak sendiri secara tidak sengaja
     */
    function recoverStuckvBTC(address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "Cannot recover to zero address");
        uint256 contractBalance = balanceOf(address(this));
        require(contractBalance >= amount, "Insufficient vBTC in contract");
        
        // Transfer langsung tanpa menggunakan _transfer untuk menghindari reentrancy
        _transfer(address(this), to, amount);
    }
}

/**
 * @dev Interface minimal untuk ERC20
 */
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}