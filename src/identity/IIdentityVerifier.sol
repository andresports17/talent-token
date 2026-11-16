// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Automated identity source used by ComplianceRegistry (KYC) and TalentRegistry (ID + 18+).
interface IIdentityVerifier {
    /// @return ok   wallet holds a valid credential proving a completed ID check by an adult (18+)
    /// @return ref  reference to the credential (e.g. EAS attestation uid); no personal data
    function verifiedAdult(address wallet) external view returns (bool ok, bytes32 ref);

    /// @return ok       wallet holds a valid country-of-residence credential
    /// @return country  ISO 3166-1 alpha-2 code, e.g. "US"
    function verifiedCountry(address wallet) external view returns (bool ok, bytes2 country);
}
