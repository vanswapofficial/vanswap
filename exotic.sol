// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Exotic Token (EXO)
 * @dev Token ERC20 standar dengan max supply 23,000 token
 */
contract ExoticToken is ERC20, Ownable {
    uint256 public constant MAX_SUPPLY = 23000 * 10**18; // 23,000 EXO
    
    bool private _initialSupplyMinted = false;
    
    /**
     * @dev Constructor - deployer menjadi owner
     */
    constructor() ERC20("Exotic Token", "EXO") {
        // Deployer otomatis menjadi owner
        // Tidak ada mint di constructor
    }
    
    /**
     * @dev Mint seluruh supply ke owner (hanya sekali)
     */
    function mintInitialSupply() external onlyOwner {
        require(!_initialSupplyMinted, "EXO: Supply already minted");
        
        _initialSupplyMinted = true;
        _mint(msg.sender, MAX_SUPPLY);
    }
    
    /**
     * @dev Override decimals
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }
    
    /**
     * @dev Cek status mint
     */
    function isInitialSupplyMinted() external view returns (bool) {
        return _initialSupplyMinted;
    }
    
    /**
     * @dev Rescue token yang tidak sengaja dikirim
     */
    function rescueTokens(address tokenAddress, uint256 amount) external onlyOwner {
        require(tokenAddress != address(this), "EXO: Cannot withdraw EXO");
        
        IERC20 token = IERC20(tokenAddress);
        token.transfer(msg.sender, amount);
    }
    
    /**
     * @dev Rescue ETH yang tidak sengaja dikirim
     */
    function rescueETH() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
    
    /**
     * @dev Menerima ETH
     */
    receive() external payable {}
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}