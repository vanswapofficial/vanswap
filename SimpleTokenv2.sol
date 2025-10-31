// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SimpleToken
 * @dev Token ERC20 sederhana untuk dibuat lewat Factory.
 * User menjadi owner kontrak dan pemilik seluruh initial supply.
 */
contract SimpleToken is ERC20, Ownable {
    uint8 private _decimals;
    bool private _initialized;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 /* initialSupply_ */
    ) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    /**
     * @dev Dipanggil sekali oleh Factory untuk mint token dan menetapkan owner.
     */
    function initialize(address owner_, uint256 initialSupply_) external {
        require(!_initialized, "Already initialized");
        _initialized = true;

        _mint(owner_, initialSupply_);
        _transferOwnership(owner_); // ✅ user menjadi owner kontrak
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
