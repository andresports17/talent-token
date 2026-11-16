// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title ComplianceRegistry
/// @notice KYC allow-list with expiry dates and country blocks.
///         Every value transfer in the Talent Token system asks this contract
///         whether a wallet is allowed.
contract ComplianceRegistry is AccessControl {
    bytes32 public constant KYC_ROLE = keccak256("KYC_ROLE");

    struct Record {
        uint64 expiresAt; // unix time when this wallet's KYC approval lapses
        bytes2 country; // ISO 3166-1 alpha-2, e.g. "US"
    }

    mapping(address => Record) public records;
    mapping(bytes2 => bool) public countryBlocked;
    /// @notice System contracts (e.g. the SupportVault) that hold tokens on behalf of others.
    mapping(address => bool) public exempt;

    event Approved(address indexed account, bytes2 country, uint64 expiresAt);
    event Revoked(address indexed account);
    event CountryBlocked(bytes2 indexed country, bool blocked);
    event ExemptSet(address indexed account, bool exempt);

    error ZeroAddress();
    error ExpiryInPast();

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(KYC_ROLE, admin);
    }

    function approve(address account, bytes2 country, uint64 expiresAt) external onlyRole(KYC_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        if (expiresAt <= block.timestamp) revert ExpiryInPast();
        records[account] = Record({expiresAt: expiresAt, country: country});
        emit Approved(account, country, expiresAt);
    }

    function revoke(address account) external onlyRole(KYC_ROLE) {
        delete records[account];
        emit Revoked(account);
    }

    function setCountryBlocked(bytes2 country, bool blocked) external onlyRole(DEFAULT_ADMIN_ROLE) {
        countryBlocked[country] = blocked;
        emit CountryBlocked(country, blocked);
    }

    function setExempt(address account, bool isExempt) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        exempt[account] = isExempt;
        emit ExemptSet(account, isExempt);
    }

    function isAllowed(address account) public view returns (bool) {
        if (exempt[account]) return true;
        Record memory r = records[account];
        return r.expiresAt > block.timestamp && !countryBlocked[r.country];
    }
}
