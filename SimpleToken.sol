// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title SimpleToken
 * @dev Token ERC20 sederhana yang digunakan oleh SimpleTokenFactory.
 * Tidak memiliki fungsi ownable atau admin — hanya fungsi `initialize()`
 * untuk mint pertama kali setelah deploy oleh factory.
 */
contract SimpleToken is ERC20 {
    uint8 private _decimals;
    bool private _initialized; // Mencegah inisialisasi ulang (mint berulang)

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 initialSupply_
    ) ERC20(name_, symbol_) {
        _decimals = decimals_;
        // Tidak ada _mint di constructor karena factory adalah deployer
    }

    /**
     * @dev Dipanggil sekali oleh factory untuk mint ke user pembuat token.
     * Tidak dapat dipanggil ulang.
     */
    function initialize(address owner_, uint256 initialSupply_) external {
        require(!_initialized, "Already initialized");
        _initialized = true;

        _mint(owner_, initialSupply_);
    }

    /**
     * @dev Override jumlah desimal (default ERC20 = 18)
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
