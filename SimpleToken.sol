// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title SimpleToken
 * @dev Token ERC20 sederhana untuk digunakan dengan SimpleTokenFactory.
 * Tidak memiliki ownable, admin, atau fungsi mint tambahan.
 */
contract SimpleToken is ERC20 {
    uint8 private _decimals;
    bool private _initialized;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 /* initialSupply_ */ // diterima untuk kompatibilitas dengan factory
    ) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    /**
     * @dev Dipanggil sekali oleh factory untuk mint ke user pembuat token.
     */
    function initialize(address owner_, uint256 initialSupply_) external {
        require(!_initialized, "Already initialized");
        _initialized = true;
        _mint(owner_, initialSupply_);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
