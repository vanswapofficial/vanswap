// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; // Import IERC20 yang benar

/**
 * @title Exotic Token (EXO)
 * @dev Token ERC20 standar dengan max supply 23,000 token, 18 decimals
 * @notice Token tanpa fungsi mint/burn setelah deployment
 */
contract ExoticToken is ERC20, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20; // Gunakan IERC20 dari OpenZeppelin
    
    // Constants
    uint256 public constant MAX_SUPPLY = 23000 * 10**18; // 23,000 token dengan 18 decimals
    uint8 public constant DECIMALS = 18;
    
    // Supply tracking
    uint256 private _totalMinted = 0;
    bool private _initialSupplyMinted = false;
    
    // Events
    event InitialSupplyMinted(address indexed to, uint256 amount);
    event ReceivedETH(address indexed from, uint256 amount);
    event ERC20Received(address indexed token, address indexed from, uint256 amount);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    event ETHRescued(address indexed to, uint256 amount);
    
    /**
     * @dev Constructor untuk Exotic Token
     * @param initialOwner Alamat pemilik kontrak yang akan menerima seluruh supply awal
     */
    constructor(address initialOwner) 
        ERC20("Exotic Token", "EXO") 
        Ownable(initialOwner)
    {
        // Tidak ada mint di constructor, mint dilakukan melalui fungsi terpisah
    }
    
    /**
     * @dev Fungsi untuk mint seluruh supply awal (hanya sekali, hanya owner)
     * @param recipient Alamat penerima seluruh supply awal
     */
    function mintInitialSupply(address recipient) external onlyOwner nonReentrant {
        require(!_initialSupplyMinted, "EXO: Initial supply already minted");
        require(recipient != address(0), "EXO: Cannot mint to zero address");
        
        _initialSupplyMinted = true;
        _totalMinted = MAX_SUPPLY;
        
        _mint(recipient, MAX_SUPPLY);
        
        emit InitialSupplyMinted(recipient, MAX_SUPPLY);
    }
    
    /**
     * @dev Override decimals function
     * @return uint8 Decimals token (18)
     */
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
    
    /**
     * @dev Mendapatkan total minted (sama dengan max supply setelah initial mint)
     * @return uint256 Total token yang sudah dimint
     */
    function totalMinted() external view returns (uint256) {
        return _totalMinted;
    }
    
    /**
     * @dev Cek apakah initial supply sudah dimint
     * @return bool Status initial mint
     */
    function isInitialSupplyMinted() external view returns (bool) {
        return _initialSupplyMinted;
    }
    
    /**
     * @dev Transfer token EXO (override dengan nonReentrant dan validasi)
     * @param to Alamat penerima
     * @param amount Jumlah token
     */
    function transfer(address to, uint256 amount) public override nonReentrant returns (bool) {
        _validateTransfer(msg.sender, to, amount);
        return super.transfer(to, amount);
    }
    
    /**
     * @dev TransferFrom token EXO (override dengan nonReentrant dan validasi)
     * @param from Alamat pengirim
     * @param to Alamat penerima
     * @param amount Jumlah token
     */
    function transferFrom(
        address from, 
        address to, 
        uint256 amount
    ) public override nonReentrant returns (bool) {
        _validateTransfer(from, to, amount);
        require(allowance(from, msg.sender) >= amount, "EXO: insufficient allowance");
        
        return super.transferFrom(from, to, amount);
    }
    
    /**
     * @dev Validasi transfer internal
     */
    function _validateTransfer(address from, address to, uint256 amount) private view {
        require(from != address(0), "EXO: transfer from zero address");
        require(to != address(0), "EXO: transfer to zero address");
        require(amount > 0, "EXO: amount must be greater than 0");
        require(balanceOf(from) >= amount, "EXO: insufficient balance");
    }
    
    /**
     * @dev Approve spending (override dengan nonReentrant)
     * @param spender Alamat yang diizinkan
     * @param amount Jumlah yang diizinkan
     */
    function approve(address spender, uint256 amount) public override nonReentrant returns (bool) {
        require(spender != address(0), "EXO: approve to zero address");
        
        // Untuk mencegah front-running attack, set ke 0 dulu jika mengubah dari non-zero
        if (amount != 0 && allowance(msg.sender, spender) != 0) {
            super.approve(spender, 0);
        }
        
        return super.approve(spender, amount);
    }
    
    /**
     * @dev Increase allowance (override dengan nonReentrant)
     * @param spender Alamat yang diizinkan
     * @param addedValue Tambahan allowance
     */
    function increaseAllowance(address spender, uint256 addedValue) public override nonReentrant returns (bool) {
        require(spender != address(0), "EXO: approve to zero address");
        require(addedValue > 0, "EXO: added value must be greater than 0");
        
        return super.increaseAllowance(spender, addedValue);
    }
    
    /**
     * @dev Decrease allowance (override dengan nonReentrant)
     * @param spender Alamat yang diizinkan
     * @param subtractedValue Pengurangan allowance
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public override nonReentrant returns (bool) {
        require(spender != address(0), "EXO: approve to zero address");
        require(subtractedValue > 0, "EXO: subtracted value must be greater than 0");
        require(allowance(msg.sender, spender) >= subtractedValue, "EXO: decreased allowance below zero");
        
        return super.decreaseAllowance(spender, subtractedValue);
    }
    
    /**
     * @dev Menerima ETH (native)
     */
    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }
    
    /**
     * @dev Fallback function
     */
    fallback() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }
    
    /**
     * @dev Fungsi untuk mengirim ETH dari kontrak (hanya owner)
     * @param to Alamat penerima
     * @param amount Jumlah ETH
     */
    function sendETH(address payable to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "EXO: send to zero address");
        require(amount > 0, "EXO: amount must be greater than 0");
        require(address(this).balance >= amount, "EXO: insufficient ETH balance");
        
        (bool success, ) = to.call{value: amount}("");
        require(success, "EXO: ETH transfer failed");
        
        emit ETHRescued(to, amount);
    }
    
    /**
     * @dev Fungsi untuk mengirim semua ETH dari kontrak (hanya owner)
     * @param to Alamat penerima
     */
    function sendAllETH(address payable to) external onlyOwner nonReentrant {
        require(to != address(0), "EXO: send to zero address");
        uint256 balance = address(this).balance;
        require(balance > 0, "EXO: no ETH balance");
        
        (bool success, ) = to.call{value: balance}("");
        require(success, "EXO: ETH transfer failed");
        
        emit ETHRescued(to, balance);
    }
    
    /**
     * @dev Fungsi untuk mengirim token ERC20 dari kontrak (hanya owner)
     * @param tokenAddress Alamat token ERC20
     * @param to Alamat penerima
     * @param amount Jumlah token
     */
    function sendERC20(
        address tokenAddress,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(tokenAddress != address(0), "EXO: invalid token address");
        require(to != address(0), "EXO: send to zero address");
        require(amount > 0, "EXO: amount must be greater than 0");
        require(tokenAddress != address(this), "EXO: use rescueEXOTokens() for EXO tokens");
        
        IERC20 token = IERC20(tokenAddress);
        uint256 tokenBalance = token.balanceOf(address(this));
        require(tokenBalance >= amount, "EXO: insufficient token balance");
        
        token.safeTransfer(to, amount);
        
        emit TokensRescued(tokenAddress, to, amount);
    }
    
    /**
     * @dev Fungsi untuk mengirim semua token ERC20 dari kontrak (hanya owner)
     * @param tokenAddress Alamat token ERC20
     * @param to Alamat penerima
     */
    function sendAllERC20(address tokenAddress, address to) external onlyOwner nonReentrant {
        require(tokenAddress != address(0), "EXO: invalid token address");
        require(to != address(0), "EXO: send to zero address");
        require(tokenAddress != address(this), "EXO: use rescueEXOTokens() for EXO tokens");
        
        IERC20 token = IERC20(tokenAddress);
        uint256 tokenBalance = token.balanceOf(address(this));
        require(tokenBalance > 0, "EXO: no token balance");
        
        token.safeTransfer(to, tokenBalance);
        
        emit TokensRescued(tokenAddress, to, tokenBalance);
    }
    
    /**
     * @dev Fungsi untuk menarik token EXO yang tidak sengaja dikirim ke kontrak (hanya owner)
     * @param to Alamat penerima
     * @param amount Jumlah token EXO
     */
    function rescueEXOTokens(address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "EXO: send to zero address");
        require(amount > 0, "EXO: amount must be greater than 0");
        
        uint256 contractBalance = balanceOf(address(this));
        require(contractBalance >= amount, "EXO: insufficient EXO balance");
        
        _transfer(address(this), to, amount);
        
        emit TokensRescued(address(this), to, amount);
    }
    
    /**
     * @dev Hook before token transfer (untuk validasi tambahan jika diperlukan)
     * @param from Alamat pengirim
     * @param to Alamat penerima
     * @param amount Jumlah token
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._beforeTokenTransfer(from, to, amount);
        
        // Tambahan validasi bisa ditambahkan di sini jika diperlukan
        // Misalnya: require(!paused, "EXO: transfers are paused");
    }
    
    /**
     * @dev Hook after token transfer (untuk logging atau aksi tambahan)
     * @param from Alamat pengirim
     * @param to Alamat penerima
     * @param amount Jumlah token
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._afterTokenTransfer(from, to, amount);
        
        // Aksi setelah transfer jika diperlukan
    }
}