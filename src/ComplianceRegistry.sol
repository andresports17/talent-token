// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IIdentityVerifier} from "./identity/IIdentityVerifier.sol";

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

    /// @notice Automated KYC source (e.g. Coinbase Verifications). Optional.
    IIdentityVerifier public identityVerifier;
    /// @notice How long a self-verified approval lasts before the wallet must re-verify.
    uint64 public autoApprovalPeriod;

    event Approved(address indexed account, bytes2 country, uint64 expiresAt);
    event Revoked(address indexed account);
    event CountryBlocked(bytes2 indexed country, bool blocked);
    event ExemptSet(address indexed account, bool exempt);

    event IdentityVerifierSet(address verifier, uint64 autoApprovalPeriod);

    error ZeroAddress();
    error ExpiryInPast();
    error NoIdentityVerifier();
    error IdentityNotVerified(address account);
    error CountryIsBlocked(bytes2 country);
    error BadPeriod();

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

    function setIdentityVerifier(IIdentityVerifier verifier, uint64 period) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (period == 0 || period > 366 days) revert BadPeriod();
        identityVerifier = verifier;
        autoApprovalPeriod = period;
        emit IdentityVerifierSet(address(verifier), period);
    }

    /// @notice Automated KYC: anyone with a valid verified-adult + country credential approves themselves.
    function selfVerify() external {
        IIdentityVerifier v = identityVerifier;
        if (address(v) == address(0)) revert NoIdentityVerifier();
        (bool adult,) = v.verifiedAdult(msg.sender);
        (bool hasCountry, bytes2 country) = v.verifiedCountry(msg.sender);
        if (!adult || !hasCountry) revert IdentityNotVerified(msg.sender);
        if (countryBlocked[country]) revert CountryIsBlocked(country);
        uint64 expiresAt = uint64(block.timestamp) + autoApprovalPeriod;
        records[msg.sender] = Record({expiresAt: expiresAt, country: country});
        emit Approved(msg.sender, country, expiresAt);
    }

    /// @notice Anyone can remove a wallet whose credential was revoked or expired.
    /// @return removed true if the wallet's approval was revoked
    function recheck(address account) external returns (bool removed) {
        IIdentityVerifier v = identityVerifier;
        if (address(v) == address(0)) revert NoIdentityVerifier();
        (bool adult,) = v.verifiedAdult(account);
        if (!adult && records[account].expiresAt != 0) {
            delete records[account];
            emit Revoked(account);
            return true;
        }
    }

    function isAllowed(address account) public view returns (bool) {
        if (exempt[account]) return true;
        Record memory r = records[account];
        return r.expiresAt > block.timestamp && !countryBlocked[r.country];
    }
}
